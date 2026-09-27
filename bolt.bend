# bolt linter config. correctness findings gate the build (error); style,
# suspicious and laws findings stay advisory (warn).
def correctness() -> String:
  "error"
def suspicious() -> String:
  "warn"
def style() -> String:
  "warn"
def laws() -> String:
  "warn"
