module L = Logseq_profile_core.Logseq_profile

let require label condition =
  if condition then Printf.printf "ok %s\n%!" label
  else (Printf.eprintf "FAIL %s\n%!" label; exit 1)

let sample =
  String.concat "\n"
    [ "title:: Durable PKM";
      "alias:: Archive, Preservation";
      "- TODO [#A] Verify [[OAIS]] package";
      "  - Link [[Fixity]] and ((2026-08-04-0859-001))";
      "- DONE Publish #archive";
      "" ]

let () =
  require "LAW LOGSEQ-CATALOG-TOTALITY"
    (List.length L.catalog >= 50 && L.catalog_violations L.catalog = []);
  require "LAW LOGSEQ-FAMILY-COVERAGE"
    (List.for_all (fun family -> L.features_in_family family <> []) L.all_families);
  let document = L.parse_document sample in
  require "LAW LOGSEQ-LOSSLESS-FILE-ROUNDTRIP"
    (String.equal (L.render_document document) sample);
  require "LAW LOGSEQ-PAGE-REFERENCE-WIKI-HOMOMORPHISM"
    (L.page_references document = [ "OAIS"; "Fixity" ] &&
     L.wiki_links document = L.page_references document);
  require "LAW LOGSEQ-BLOCK-REFERENCE-ZK-EDGE"
    (L.block_references document = [ "2026-08-04-0859-001" ] &&
     List.exists
       (fun edge -> L.edge_target edge = "2026-08-04-0859-001")
       (L.zk_edges document));
  require "LAW LOGSEQ-PROPERTY-AND-TASK-OBSERVATION"
    (List.length (L.properties document) = 2 &&
     List.length (L.tasks document) = 2);
  let counts = L.disposition_counts L.catalog in
  require "LAW LOGSEQ-HONEST-DISPOSITION-PARTITION"
    (counts.L.total = counts.exact + counts.equivalent + counts.advisory +
                      counts.unsupported + counts.unavailable &&
     counts.unsupported > 0 && counts.equivalent > 0);
  let reversed = List.rev L.catalog in
  require "PROPERTY LOGSEQ-CATALOG-ORDER-INDEPENDENCE"
    (L.disposition_counts reversed = counts);
  require "MUT-LOGSEQ-DUPLICATE-FEATURE-ID"
    (match L.catalog with
     | first :: _ -> L.catalog_violations (first :: L.catalog) <> []
     | [] -> false);
  require "LAW LOGSEQ-SOURCE-CENSUS-TOTALITY"
    (L.census_violations L.catalog L.source_census = [] &&
     List.length L.source_census = List.length L.catalog);
  require "MUT-LOGSEQ-CENSUS-1-DROPPED-SOURCE-ROW"
    (match L.source_census with
     | _ :: rest -> L.census_violations L.catalog rest <> []
     | [] -> false);
  require "LAW LOGSEQ-COMMUNITY-SOURCES-ARE-ADVISORY"
    (List.for_all
       (fun (row : L.source_row) ->
         match row.authority with
         | L.Community_advisory -> not row.executable_authority
         | L.Official_docs | L.Source_repository -> true)
       L.source_census)
