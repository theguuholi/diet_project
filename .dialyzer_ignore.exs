[
  # Ecto schema changeset calls produce false no_return warnings because
  # dialyzer cannot model Ecto.Changeset's dynamic typing and treats struct
  # literals with nil primary keys as not matching the @type t definition.
  ~r"no_return.*changeset",
  ~r"call.*changeset will not succeed",
  # Cascading false positives from the changeset no_return warnings above.
  ~r"no_return.*create_meal",
  ~r"no_return.*update_macro_log",
  ~r"no_return.*create_profile",
  ~r"no_return.*create_goals",
  ~r"no_return.*create_plan",
  ~r"no_return.*create_subscription",
  ~r"no_return.*profile_fixture",
  ~r"no_return.*goals_fixture",
  ~r"no_return.*plan_fixture",
  ~r"no_return.*subscription_fixture",
  ~r"no_return.*meal_fixture",
  # Anonymous function closures in fixtures call the above no_return functions.
  ~r"anonymous function has no local return",
  # ExAws R2 client: dialyzer cannot resolve the ExAws.S3.put_object return type.
  ~r"no_return.*upload",
  ~r"call.*request will not succeed",
  # Bot FSM: dialyzer cannot model the full union of FSM state transitions so it
  # reports extra_range for advance_state/2 and pattern_match_cov for the
  # catch-all do_transition/2 clause. Both are intentional and forward-compatible.
  ~r"extra_range.*advance_state",
  ~r"pattern_match_cov",
  # Bot.finish_onboarding/2 — cascades from create_profile no_return above.
  ~r"no_return.*finish_onboarding",
  # Dialyzer incorrectly flags unused helpers in process_text_meal when the
  # with-chain before them is inferred as no_return due to create_meal above.
  ~r"unused_fun.*macro_log_to_map",
  ~r"unused_fun.*goals_to_map"
]
