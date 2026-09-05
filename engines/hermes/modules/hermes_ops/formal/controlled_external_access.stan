// Reliability calibration model for R31 predictive observations. stanc must
// compile this artifact through a future controlled OCaml oracle owner before
// it grants evidence. Posterior output is report-only and never authorizes an
// external effect.
data {
  int<lower=1> N;
  int<lower=1> K;
  array[N] int<lower=1, upper=K> family;
  array[N] int<lower=0, upper=1> observed_failure;
  real<lower=0> prior_alpha;
  real<lower=0> prior_beta;
}
parameters {
  vector<lower=0, upper=1>[K] failure_probability;
}
model {
  failure_probability ~ beta(prior_alpha, prior_beta);
  observed_failure ~ bernoulli(failure_probability[family]);
}
generated quantities {
  array[N] int<lower=0, upper=1> posterior_predictive_failure;
  vector[N] log_likelihood;
  for (n in 1:N) {
    posterior_predictive_failure[n] = bernoulli_rng(failure_probability[family[n]]);
    log_likelihood[n] = bernoulli_lpmf(observed_failure[n] | failure_probability[family[n]]);
  }
}
