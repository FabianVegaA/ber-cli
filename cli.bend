import Base
import ./src/Run.bend as Run

def main() -> IO(Unit):
  do IO<Unit>:
    argv : List<String> <- IO.args()
    Run.run_argv(argv)
