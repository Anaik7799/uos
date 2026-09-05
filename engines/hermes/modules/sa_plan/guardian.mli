open Core

type proposal = {
  diff : string;
  payload : string;
}

val validate_proposal : proposal -> (unit, string) result
