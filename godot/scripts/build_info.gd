extends Object

# Build identifier values. Overwritten in CI by a step that injects the
# current git short SHA and commit timestamp before each Godot export.
# These placeholder values are what you see when running outside CI
# (or if the CI injection step ever fails to run).

const SHA: String = "local-dev"
const SHORT_DATE: String = "0000-00-00"
const ITER: String = "?"
