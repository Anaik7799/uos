(* SC-PROVENANCE-001 — bounded predictive OODA loop over recorded KM metrics.

   Observe  run the gate against the working tree
   Orient   append the observation to an append-only history and fit a trend
   Decide   compare level and projection against the contract thresholds
   Act      emit a report. This loop has NO effect authority: it never writes a
            document, never changes admission state, and never dispatches work.

   The forecast is the simplest defensible estimator: an EWMA level, an
   ordinary-least-squares slope, and the RMS residual of the series against its
   own fitted line. The residual is reported alongside every projection, because
   a slope without its residual is not a forecast. The Mojo kernel computes the
   same three quantities behind the NIF; the two implementations are compared as
   a differential oracle. *)

exception Invalid of string
let require c m = if not c then raise (Invalid m)

let schema = {sql|
CREATE TABLE IF NOT EXISTS metric_snapshot (
  sequence      INTEGER PRIMARY KEY,
  observed_utc  TEXT NOT NULL,
  metric        TEXT NOT NULL,
  value         REAL NOT NULL,
  plan_id       TEXT NOT NULL,
  digest        TEXT NOT NULL
);
CREATE TRIGGER IF NOT EXISTS metric_no_update BEFORE UPDATE ON metric_snapshot
BEGIN SELECT RAISE(ABORT, 'metric snapshots are append-only'); END;
CREATE TRIGGER IF NOT EXISTS metric_no_delete BEFORE DELETE ON metric_snapshot
BEGIN SELECT RAISE(ABORT, 'metric snapshots are append-only'); END;
|sql}

let ok rc = require (rc = Sqlite3.Rc.OK) "sqlite operation failed"
let sha256 s = Cryptokit.(transform_string (Hexa.encode ()) (hash_string (Hash.sha256 ()) s))

let ensure db = ok (Sqlite3.exec db schema)

let record db ~observed ~metric ~value ~plan =
  ensure db;
  let stmt = Sqlite3.prepare db
    "INSERT INTO metric_snapshot (observed_utc,metric,value,plan_id,digest) VALUES (?,?,?,?,?)" in
  Fun.protect ~finally:(fun () -> ignore (Sqlite3.finalize stmt)) (fun () ->
    let d = sha256 (String.concat "\x1f" [observed; metric; string_of_float value; plan]) in
    ok (Sqlite3.bind_text stmt 1 observed);
    ok (Sqlite3.bind_text stmt 2 metric);
    ok (Sqlite3.bind_double stmt 3 value);
    ok (Sqlite3.bind_text stmt 4 plan);
    ok (Sqlite3.bind_text stmt 5 d);
    require (Sqlite3.step stmt = Sqlite3.Rc.DONE) "metric insert refused")

let series db ~metric =
  ensure db;
  let stmt = Sqlite3.prepare db
    "SELECT value FROM metric_snapshot WHERE metric=? ORDER BY sequence LIMIT 10000" in
  Fun.protect ~finally:(fun () -> ignore (Sqlite3.finalize stmt)) (fun () ->
    ok (Sqlite3.bind_text stmt 1 metric);
    let rec loop acc = match Sqlite3.step stmt with
      | Sqlite3.Rc.ROW ->
        (match Sqlite3.column stmt 0 with
         | Sqlite3.Data.FLOAT f -> loop (f :: acc)
         | Sqlite3.Data.INT n -> loop (Int64.to_float n :: acc)
         | _ -> loop acc)
      | Sqlite3.Rc.DONE -> List.rev acc
      | _ -> raise (Invalid "metric scan failed") in
    loop [])

(* --- estimators, independent of the Mojo kernel -------------------------- *)

let ewma alpha xs =
  require (alpha > 0.0 && alpha <= 1.0) "alpha out of range";
  match xs with
  | [] -> None
  | h :: t -> Some (List.fold_left (fun lvl x -> (alpha *. x) +. ((1.0 -. alpha) *. lvl)) h t)

let fit xs =
  let n = List.length xs in
  if n < 2 then None
  else begin
    let nf = float_of_int n in
    let (sx, sy, sxy, sxx) =
      List.fold_left (fun (a, b, c, d) (i, y) ->
        let x = float_of_int i in
        (a +. x, b +. y, c +. (x *. y), d +. (x *. x)))
        (0.0, 0.0, 0.0, 0.0)
        (List.mapi (fun i y -> (i, y)) xs) in
    let denom = (nf *. sxx) -. (sx *. sx) in
    if denom = 0.0 then None
    else begin
      let slope = ((nf *. sxy) -. (sx *. sy)) /. denom in
      let intercept = (sy -. (slope *. sx)) /. nf in
      let sse = List.fold_left (fun acc (i, y) ->
        let p = intercept +. (slope *. float_of_int i) in
        acc +. ((y -. p) *. (y -. p))) 0.0 (List.mapi (fun i y -> (i, y)) xs) in
      Some (slope, intercept, sqrt (sse /. nf))
    end
  end

(* Projection k steps beyond the last observation, with the residual as its
   honest half-width. A projection whose band spans the threshold decides
   nothing, and says so. *)
type projection = {
  slope : float;
  residual : float;
  projected : float;
  low : float;
  high : float;
  decisive : bool;
}

let project xs ~steps ~threshold =
  match fit xs with
  | None -> None
  | Some (slope, intercept, residual) ->
    let n = List.length xs in
    let at = float_of_int (n - 1 + steps) in
    let p = intercept +. (slope *. at) in
    let low = p -. residual and high = p +. residual in
    Some { slope; residual; projected = p; low; high;
           decisive = not (low <= threshold && threshold <= high) }
