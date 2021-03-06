#' Expected Values of the Posterior Predictive Distribution
#' 
#' Compute posterior samples of the expected value/mean of the posterior
#' predictive distribution. Can be performed for the data used to fit the model
#' (posterior predictive checks) or for new data. By definition, these
#' predictions have smaller variance than the posterior predictions performed by
#' the \code{\link{posterior_predict.brmsfit}} method. This is because only the
#' uncertainty in the mean is incorporated in the samples computed by
#' \code{pp_expect} while any residual error is ignored. However, the estimated
#' means of both methods averaged across samples should be very similar.
#' 
#' @inheritParams posterior_predict.brmsfit
#' @param dpar Optional name of a predicted distributional parameter.
#'  If specified, fitted values of this parameters are returned.
#' @param nlpar Optional name of a predicted non-linear parameter.
#'  If specified, fitted values of this parameters are returned.
#'  
#' @return An \code{array} of predicted \emph{mean} response values. For
#'   categorical and ordinal models, the output is an S x N x C array.
#'   Otherwise, the output is an S x N matrix, where S is the number of
#'   posterior samples, N is the number of observations, and C is the number of
#'   categories. In multivariate models, an additional dimension is added to the
#'   output which indexes along the different response variables.
#'   
#' @details \code{NA} values within factors in \code{newdata}, 
#'   are interpreted as if all dummy variables of this factor are 
#'   zero. This allows, for instance, to make predictions of the grand mean 
#'   when using sum coding.
#'
#' @examples 
#' \dontrun{
#' ## fit a model
#' fit <- brm(rating ~ treat + period + carry + (1|subject), 
#'            data = inhaler)
#' 
#' ## extract fitted values
#' ppe <- pp_expect(fit)
#' str(ppe)
#' }
#' 
#' @export 
pp_expect.brmsfit <- function(object, newdata = NULL, re_formula = NULL,
                              re.form = NULL, resp = NULL, dpar = NULL,
                              nlpar = NULL, nsamples = NULL, subset = NULL, 
                              sort = FALSE, ...) {
  cl <- match.call()
  if ("re.form" %in% names(cl)) {
    re_formula <- re.form
  }
  contains_samples(object)
  object <- restructure(object)
  draws <- extract_draws(
    object, newdata = newdata, re_formula = re_formula, resp = resp, 
    nsamples = nsamples, subset = subset, check_response = FALSE, ...
  )
  pp_expect(
    draws, scale = "response", dpar = dpar, 
    nlpar = nlpar, sort = sort, summary = FALSE
  )
}

#' @rdname pp_expect.brmsfit
#' @export
pp_expect <- function(object, ...) {
  UseMethod("pp_expect")
}

#' @export
pp_expect.mvbrmsdraws <- function(object, ...) {
  out <- lapply(object$resps, pp_expect, ...)
  along <- ifelse(length(out) > 1L, 3, 2)
  do_call(abind, c(out, along = along))
}

#' @export
pp_expect.brmsdraws <- function(object, scale, dpar, nlpar, sort, 
                                summary, robust, probs, ...) {
  dpars <- names(object$dpars)
  nlpars <- names(object$nlpars)
  if (length(dpar)) {
    # predict a distributional parameter
    dpar <- as_one_character(dpar)
    if (!dpar %in% dpars) {
      stop2("Invalid argument 'dpar'. Valid distributional ",
            "parameters are: ", collapse_comma(dpars))
    }
    if (length(nlpar)) {
      stop2("Cannot use 'dpar' and 'nlpar' at the same time.")
    }
    predicted <- is.bdrawsl(object$dpars[[dpar]]) ||
      is.bdrawsnl(object$dpars[[dpar]])
    if (predicted) {
      # parameter varies across observations
      if (scale == "linear") {
        object$dpars[[dpar]]$family$link <- "identity"
      }
      if (is_ordinal(object$family)) {
        object$dpars[[dpar]]$cs <- NULL
        object$family <- object$dpars[[dpar]]$family <- 
          .dpar_family(link = object$dpars[[dpar]]$family$link)
      }
      if (dpar_class(dpar) == "theta" && scale == "response") {
        ap_id <- as.numeric(dpar_id(dpar))
        out <- get_theta(object)[, , ap_id, drop = FALSE]
        dim(out) <- dim(out)[c(1, 2)]
      } else {
        out <- get_dpar(object, dpar = dpar, ilink = TRUE)
      }
    } else {
      # parameter is constant across observations
      out <- object$dpars[[dpar]]
      out <- matrix(out, nrow = object$nsamples, ncol = object$nobs)
    }
  } else if (length(nlpar)) {
    # predict a non-linear parameter
    nlpar <- as_one_character(nlpar)
    if (!nlpar %in% nlpars) {
      stop2("Invalid argument 'nlpar'. Valid non-linear ",
            "parameters are: ", collapse_comma(nlpars))
    }
    out <- get_nlpar(object, nlpar = nlpar)
  } else {
    # predict the mean of the response distribution
    if (scale == "response") {
      for (nlp in nlpars) {
        object$nlpars[[nlp]] <- get_nlpar(object, nlpar = nlp)
      }
      for (dp in dpars) {
        object$dpars[[dp]] <- get_dpar(object, dpar = dp)
      }
      if (is_trunc(object)) {
        out <- pp_expect_trunc(object)
      } else {
        pp_expect_fun <- paste0("pp_expect_", object$family$family)
        pp_expect_fun <- get(pp_expect_fun, asNamespace("brms"))
        out <- pp_expect_fun(object)
      }
    } else {
      if (conv_cats_dpars(object$family)) {
        mus <- dpars[grepl("^mu", dpars)] 
      } else {
        mus <- dpars[dpar_class(dpars) %in% "mu"]
      }
      if (length(mus) == 1L) {
        out <- get_dpar(object, dpar = mus, ilink = FALSE)
      } else {
        # multiple mu parameters in categorical or mixture models
        out <- lapply(mus, get_dpar, draws = object, ilink = FALSE)
        out <- abind::abind(out, along = 3)
      }
    }
  }
  if (is.null(dim(out))) {
    out <- as.matrix(out)
  }
  colnames(out) <- NULL
  out <- reorder_obs(out, object$old_order, sort = sort)
  if (summary) {
    # only for compatibility with the 'fitted' method
    out <- posterior_summary(out, probs = probs, robust = robust)
    if (has_cat(object$family) && length(dim(out)) == 3L) {
      if (scale == "linear") {
        dimnames(out)[[3]] <- paste0("eta", seq_dim(out, 3))
      } else {
        dimnames(out)[[3]] <- paste0("P(Y = ", dimnames(out)[[3]], ")")
      }
    }
  }
  out
}

#' Expected Values of the Posterior Predictive Distribution
#' 
#' This method is an alias of \code{\link{pp_expect.brmsfit}}
#' with additional arguments for obtaining summaries of the computed samples.
#' 
#' @inheritParams pp_expect.brmsfit
#' @param object An object of class \code{brmsfit}.
#' @param scale Either \code{"response"} or \code{"linear"}. 
#'  If \code{"response"}, results are returned on the scale 
#'  of the response variable. If \code{"linear"},
#'  results are returned on the scale of the linear predictor term,
#'  that is without applying the inverse link function or
#'  other transformations.
#' @param summary Should summary statistics be returned
#'  instead of the raw values? Default is \code{TRUE}..
#' @param robust If \code{FALSE} (the default) the mean is used as 
#'  the measure of central tendency and the standard deviation as 
#'  the measure of variability. If \code{TRUE}, the median and the 
#'  median absolute deviation (MAD) are applied instead.
#'  Only used if \code{summary} is \code{TRUE}.
#' @param probs The percentiles to be computed by the \code{quantile} 
#'  function. Only used if \code{summary} is \code{TRUE}. 
#' 
#' @return An \code{array} of predicted \emph{mean} response values.
#'   If \code{summary = FALSE} the output resembles those of 
#'   \code{\link{pp_expect.brmsfit}}.
#' 
#'   If \code{summary = TRUE} the output depends on the family: For categorical
#'   and ordinal families, the output is an N x E x C array, where N is the
#'   number of observations, E is the number of summary statistics, and C is the
#'   number of categories. For all other families, the output is an N x E
#'   matrix. The number of summary statistics E is equal to \code{2 +
#'   length(probs)}: The \code{Estimate} column contains point estimates (either
#'   mean or median depending on argument \code{robust}), while the
#'   \code{Est.Error} column contains uncertainty estimates (either standard
#'   deviation or median absolute deviation depending on argument
#'   \code{robust}). The remaining columns starting with \code{Q} contain
#'   quantile estimates as specifed via argument \code{probs}.
#'   
#'   In multivariate models, an additional dimension is added to the output
#'   which indexes along the different response variables.
#' 
#' @seealso \code{\link{pp_expect.brmsfit}} 
#'
#' @examples 
#' \dontrun{
#' ## fit a model
#' fit <- brm(rating ~ treat + period + carry + (1|subject), 
#'            data = inhaler)
#' 
#' ## extract fitted values
#' fitted_values <- fitted(fit)
#' head(fitted_values)
#' 
#' ## plot fitted means against actual response
#' dat <- as.data.frame(cbind(Y = standata(fit)$Y, fitted_values))
#' ggplot(dat) + geom_point(aes(x = Estimate, y = Y))
#' }
#' 
#' @export
fitted.brmsfit <- function(object, newdata = NULL, re_formula = NULL,
                           scale = c("response", "linear"),
                           resp = NULL, dpar = NULL, nlpar = NULL,
                           nsamples = NULL, subset = NULL, sort = FALSE, 
                           summary = TRUE, robust = FALSE, 
                           probs = c(0.025, 0.975), ...) {
  scale <- match.arg(scale)
  summary <- as_one_logical(summary)
  contains_samples(object)
  object <- restructure(object)
  draws <- extract_draws(
    object, newdata = newdata, re_formula = re_formula, resp = resp, 
    nsamples = nsamples, subset = subset, check_response = FALSE, ...
  )
  pp_expect(
    draws, scale = scale, dpar = dpar, nlpar = nlpar, sort = sort, 
    summary = summary, robust = robust, probs = probs
  )
}

#' Posterior Samples of the Linear Predictor
#' 
#' Compute posterior samples of the linear predictor, that is samples before
#' applying any link functions or other transformations. Can be performed for
#' the data used to fit the model (posterior predictive checks) or for new data.
#' 
#' @inheritParams pp_expect.brmsfit
#' @param object An object of class \code{brmsfit}.
#' @param transform (Deprecated) Logical; if \code{FALSE}
#'  (the default), samples of the linear predictor are returned.
#'  If \code{TRUE}, samples of transformed linear predictor,
#'  that is, the mean of the posterior predictive distribution
#'  are returned instead (see \code{\link{pp_expect}} for details).
#'  Only implemented for compatibility with the 
#'  \code{\link[rstantools:posterior_linpred]{posterior_linpred}}
#'  generic. 
#' 
#' @seealso \code{\link{pp_expect.brmsfit}}
#'  
#' @examples 
#' \dontrun{
#' ## fit a model
#' fit <- brm(rating ~ treat + period + carry + (1|subject), 
#'            data = inhaler)
#' 
#' ## extract linear predictor values
#' pl <- posterior_linpred(fit)
#' str(pl)
#' }
#'
#' @aliases posterior_linpred
#' @method posterior_linpred brmsfit
#' @importFrom rstantools posterior_linpred
#' @export
#' @export posterior_linpred
posterior_linpred.brmsfit <- function(
  object, transform = FALSE, newdata = NULL, re_formula = NULL,
  re.form = NULL, resp = NULL, dpar = NULL, nlpar = NULL, 
  nsamples = NULL, subset = NULL, sort = FALSE, ...
) {
  cl <- match.call()
  if ("re.form" %in% names(cl)) {
    re_formula <- re.form
  }
  scale <- "linear"
  transform <- as_one_logical(transform)
  if (transform) {
    warning2("posterior_linpred(transform = TRUE) is deprecated. Please ",
             "use pp_expect() instead, without the 'transform' argument.")
    scale <- "response"
  }
  contains_samples(object)
  object <- restructure(object)
  draws <- extract_draws(
    object, newdata = newdata, re_formula = re_formula, resp = resp, 
    nsamples = nsamples, subset = subset, check_response = FALSE, ...
  )
  pp_expect(
    draws, scale = scale, dpar = dpar, 
    nlpar = nlpar, sort = sort, summary = FALSE
  )
}

# ------------------- family specific pp_expect methods ---------------------
# All pp_expect_<family> functions have the same arguments structure
# @param draws A named list returned by extract_draws containing 
#   all required data and samples
# @return transformed linear predictor representing the mean
#   of the response distribution
pp_expect_gaussian <- function(draws) {
  if (!is.null(draws$ac$lagsar)) {
    draws$dpars$mu <- pp_expect_lagsar(draws)
  }
  draws$dpars$mu
}

pp_expect_student <- function(draws) {
  if (!is.null(draws$ac$lagsar)) {
    draws$dpars$mu <- pp_expect_lagsar(draws)
  }
  draws$dpars$mu
}

pp_expect_skew_normal <- function(draws) {
  draws$dpars$mu
}

pp_expect_lognormal <- function(draws) {
  with(draws$dpars, exp(mu + sigma^2 / 2))
}

pp_expect_shifted_lognormal <- function(draws) {
  with(draws$dpars, exp(mu + sigma^2 / 2) + ndt)
}

pp_expect_binomial <- function(draws) {
  trials <- as_draws_matrix(draws$data$trials, dim_mu(draws))
  draws$dpars$mu * trials 
}

pp_expect_bernoulli <- function(draws) {
  draws$dpars$mu
}

pp_expect_poisson <- function(draws) {
  draws$dpars$mu
}

pp_expect_negbinomial <- function(draws) {
  draws$dpars$mu
}

pp_expect_geometric <- function(draws) {
  draws$dpars$mu
}

pp_expect_discrete_weibull <- function(draws) {
  mean_discrete_weibull(draws$dpars$mu, draws$dpars$shape)
}

pp_expect_com_poisson <- function(draws) {
  mean_com_poisson(draws$dpars$mu, draws$dpars$shape)
}

pp_expect_exponential <- function(draws) {
  draws$dpars$mu
}

pp_expect_gamma <- function(draws) {
  draws$dpars$mu
}

pp_expect_weibull <- function(draws) {
  draws$dpars$mu
}

pp_expect_frechet <- function(draws) {
  draws$dpars$mu
}

pp_expect_gen_extreme_value <- function(draws) {
  with(draws$dpars, mu + sigma * (gamma(1 - xi) - 1) / xi)
}

pp_expect_inverse.gaussian <- function(draws) {
  draws$dpars$mu
}

pp_expect_exgaussian <- function(draws) {
  draws$dpars$mu
}

pp_expect_wiener <- function(draws) {
  # mu is the drift rate
  with(draws$dpars,
   ndt - bias / mu + bs / mu * 
     (exp(-2 * mu * bias) - 1) / (exp(-2 * mu * bs) - 1)
  )
}

pp_expect_beta <- function(draws) {
  draws$dpars$mu
}

pp_expect_von_mises <- function(draws) {
  draws$dpars$mu
}

pp_expect_asym_laplace <- function(draws) {
  with(draws$dpars, 
    mu + sigma * (1 - 2 * quantile) / (quantile * (1 - quantile))
  )
}

pp_expect_zero_inflated_asym_laplace <- function(draws) {
  pp_expect_asym_laplace(draws) * (1 - draws$dpars$zi)
}

pp_expect_cox <- function(draws) {
  stop2("Cannot compute expected values of the posterior predictive ",
        "distribution for family 'cox'.")
}

pp_expect_hurdle_poisson <- function(draws) {
  with(draws$dpars, mu / (1 - exp(-mu)) * (1 - hu))
}

pp_expect_hurdle_negbinomial <- function(draws) {
  with(draws$dpars, mu / (1 - (shape / (mu + shape))^shape) * (1 - hu))
}

pp_expect_hurdle_gamma <- function(draws) {
  with(draws$dpars, mu * (1 - hu))
}

pp_expect_hurdle_lognormal <- function(draws) {
  with(draws$dpars, exp(mu + sigma^2 / 2) * (1 - hu))
}

pp_expect_zero_inflated_poisson <- function(draws) {
  with(draws$dpars, mu * (1 - zi))
}

pp_expect_zero_inflated_negbinomial <- function(draws) {
  with(draws$dpars, mu * (1 - zi))  
}

pp_expect_zero_inflated_binomial <- function(draws) {
  trials <- as_draws_matrix(draws$data$trials, dim_mu(draws))
  draws$dpars$mu * trials * (1 - draws$dpars$zi)
}

pp_expect_zero_inflated_beta <- function(draws) {
  with(draws$dpars, mu * (1 - zi)) 
}

pp_expect_zero_one_inflated_beta <- function(draws) {
  with(draws$dpars, zoi * coi + mu * (1 - zoi))
}

pp_expect_categorical <- function(draws) {
  get_probs <- function(i) {
    eta <- insert_refcat(extract_col(eta, i), family = draws$family)
    dcategorical(cats, eta = eta)
  }
  eta <- abind(draws$dpars, along = 3)
  cats <- seq_len(draws$data$ncat)
  out <- abind(lapply(seq_cols(eta), get_probs), along = 3)
  out <- aperm(out, perm = c(1, 3, 2))
  dimnames(out)[[3]] <- draws$cats
  out
}

pp_expect_multinomial <- function(draws) {
  get_counts <- function(i) {
    eta <- insert_refcat(extract_col(eta, i), family = draws$family)
    dcategorical(cats, eta = eta) * trials[i]
  }
  eta <- abind(draws$dpars, along = 3)
  cats <- seq_len(draws$data$ncat)
  trials <- draws$data$trials
  out <- abind(lapply(seq_cols(eta), get_counts), along = 3)
  out <- aperm(out, perm = c(1, 3, 2))
  dimnames(out)[[3]] <- draws$cats
  out
}

pp_expect_dirichlet <- function(draws) {
  get_probs <- function(i) {
    eta <- insert_refcat(extract_col(eta, i), family = draws$family)
    dcategorical(cats, eta = eta)
  }
  eta <- draws$dpars[grepl("^mu", names(draws$dpars))]
  eta <- abind(eta, along = 3)
  cats <- seq_len(draws$data$ncat)
  out <- abind(lapply(seq_cols(eta), get_probs), along = 3)
  out <- aperm(out, perm = c(1, 3, 2))
  dimnames(out)[[3]] <- draws$cats
  out
}

pp_expect_cumulative <- function(draws) {
  pp_expect_ordinal(draws)
}

pp_expect_sratio <- function(draws) {
  pp_expect_ordinal(draws)
}

pp_expect_cratio <- function(draws) {
  pp_expect_ordinal(draws)
}

pp_expect_acat <- function(draws) {
  pp_expect_ordinal(draws)
}

pp_expect_custom <- function(draws) {
  pp_expect_fun <- draws$family$pp_expect
  if (!is.function(pp_expect_fun)) {
    pp_expect_fun <- paste0("pp_expect_", draws$family$name)
    pp_expect_fun <- get(pp_expect_fun, draws$family$env)
  }
  pp_expect_fun(draws)
}

pp_expect_mixture <- function(draws) {
  families <- family_names(draws$family)
  draws$dpars$theta <- get_theta(draws)
  out <- 0
  for (j in seq_along(families)) {
    pp_expect_fun <- paste0("pp_expect_", families[j])
    pp_expect_fun <- get(pp_expect_fun, asNamespace("brms"))
    tmp_draws <- pseudo_draws_for_mixture(draws, j)
    if (length(dim(draws$dpars$theta)) == 3L) {
      theta <- draws$dpars$theta[, , j]
    } else {
      theta <- draws$dpars$theta[, j]
    }
    out <- out + theta * pp_expect_fun(tmp_draws)
  }
  out
}

# ------ pp_expect helper functions ------
# compute 'pp_expect' for ordinal models
pp_expect_ordinal <- function(draws) {
  dens <- get(paste0("d", draws$family$family), mode = "function")
  ncat_max <- max(draws$data$nthres) + 1
  nact_min <- min(draws$data$nthres) + 1
  zero_mat <- matrix(0, nrow = draws$nsamples, ncol = ncat_max - nact_min)
  args <- list(link = draws$family$link)
  out <- vector("list", draws$nobs)
  for (i in seq_along(out)) {
    args_i <- args
    args_i$eta <- extract_col(draws$dpars$mu, i)
    args_i$disc <- extract_col(draws$dpars$disc, i)
    args_i$thres <- subset_thres(draws, i)
    ncat_i <- NCOL(args_i$thres) + 1
    args_i$x <- seq_len(ncat_i)
    out[[i]] <- do_call(dens, args_i)
    if (ncat_i < ncat_max) {
      sel <- seq_len(ncat_max - ncat_i)
      out[[i]] <- cbind(out[[i]], zero_mat[, sel])
    }
  }
  out <- abind(out, along = 3)
  out <- aperm(out, perm = c(1, 3, 2))
  dimnames(out)[[3]] <- seq_len(ncat_max)
  out
}

# compute 'pp_expect' for lagsar models
pp_expect_lagsar <- function(draws) {
  stopifnot(!is.null(draws$ac$lagsar))
  I <- diag(draws$nobs)
  .pp_expect <- function(s) {
    IB <- I - with(draws$ac, lagsar[s, ] * Msar)
    as.numeric(solve(IB, draws$dpars$mu[s, ]))
  }
  out <- rblapply(seq_len(draws$nsamples), .pp_expect)
  rownames(out) <- NULL
  out
}

# expand data to dimension appropriate for
# vectorized multiplication with posterior samples
as_draws_matrix <- function(x, dim) {
  stopifnot(length(dim) == 2L, length(x) %in% c(1, dim[2]))
  matrix(x, nrow = dim[1], ncol = dim[2], byrow = TRUE)
}

# expected dimension of the main parameter 'mu'
dim_mu <- function(draws) {
  c(draws$nsamples, draws$nobs)
}

# is the model truncated?
is_trunc <- function(draws) {
  stopifnot(is.brmsdraws(draws))
  any(draws$data[["lb"]] > -Inf) || any(draws$data[["ub"]] < Inf)
}

# prepares data required for truncation and calles the 
# family specific truncation function for pp_expect values
pp_expect_trunc <- function(draws) {
  stopifnot(is_trunc(draws))
  lb <- as_draws_matrix(draws$data[["lb"]], dim_mu(draws))
  ub <- as_draws_matrix(draws$data[["ub"]], dim_mu(draws))
  pp_expect_trunc_fun <- paste0("pp_expect_trunc_", draws$family$family)
  pp_expect_trunc_fun <- try(
    get(pp_expect_trunc_fun, asNamespace("brms")), 
    silent = TRUE
  )
  if (is(pp_expect_trunc_fun, "try-error")) {
    stop2("pp_expect values on the respone scale not yet implemented ",
          "for truncated '", draws$family$family, "' models.")
  }
  trunc_args <- nlist(draws, lb, ub)
  do_call(pp_expect_trunc_fun, trunc_args)
}

# ----- family specific truncation functions -----
# @param draws output of 'extract_draws'
# @param lb lower truncation bound
# @param ub upper truncation bound
# @return samples of the truncated mean parameter
pp_expect_trunc_gaussian <- function(draws, lb, ub) {
  zlb <- (lb - draws$dpars$mu) / draws$dpars$sigma
  zub <- (ub - draws$dpars$mu) / draws$dpars$sigma
  # truncated mean of standard normal; see Wikipedia
  trunc_zmean <- (dnorm(zlb) - dnorm(zub)) / (pnorm(zub) - pnorm(zlb))  
  draws$dpars$mu + trunc_zmean * draws$dpars$sigma  
}

pp_expect_trunc_student <- function(draws, lb, ub) {
  zlb <- with(draws$dpars, (lb - mu) / sigma)
  zub <- with(draws$dpars, (ub - mu) / sigma)
  nu <- draws$dpars$nu
  # see Kim 2008: Moments of truncated Student-t distribution
  G1 <- gamma((nu - 1) / 2) * nu^(nu / 2) / 
    (2 * (pt(zub, df = nu) - pt(zlb, df = nu))
     * gamma(nu / 2) * gamma(0.5))
  A <- (nu + zlb^2) ^ (-(nu - 1) / 2)
  B <- (nu + zub^2) ^ (-(nu - 1) / 2)
  trunc_zmean <- G1 * (A - B)
  draws$dpars$mu + trunc_zmean * draws$dpars$sigma 
}

pp_expect_trunc_lognormal <- function(draws, lb, ub) {
  lb <- ifelse(lb < 0, 0, lb)
  m1 <- with(draws$dpars, 
    exp(mu + sigma^2 / 2) * 
      (pnorm((log(ub) - mu) / sigma - sigma) - 
       pnorm((log(lb) - mu) / sigma - sigma))
  )
  with(draws$dpars, 
    m1 / (plnorm(ub, meanlog = mu, sdlog = sigma) - 
          plnorm(lb, meanlog = mu, sdlog = sigma))
  )
}

pp_expect_trunc_gamma <- function(draws, lb, ub) {
  lb <- ifelse(lb < 0, 0, lb)
  draws$dpars$scale <- draws$dpars$mu / draws$dpars$shape
  # see Jawitz 2004: Moments of truncated continuous univariate distributions
  m1 <- with(draws$dpars, 
    scale / gamma(shape) * 
      (incgamma(1 + shape, ub / scale) - 
       incgamma(1 + shape, lb / scale))
  )
  with(draws$dpars, 
    m1 / (pgamma(ub, shape, scale = scale) - 
          pgamma(lb, shape, scale = scale))
  )
}

pp_expect_trunc_exponential <- function(draws, lb, ub) {
  lb <- ifelse(lb < 0, 0, lb)
  inv_mu <- 1 / draws$dpars$mu
  # see Jawitz 2004: Moments of truncated continuous univariate distributions
  m1 <- with(draws$dpars, mu * (incgamma(2, ub / mu) - incgamma(2, lb / mu)))
  m1 / (pexp(ub, rate = inv_mu) - pexp(lb, rate = inv_mu))
}

pp_expect_trunc_weibull <- function(draws, lb, ub) {
  lb <- ifelse(lb < 0, 0, lb)
  draws$dpars$a <- 1 + 1 / draws$dpars$shape
  draws$dpars$scale <- with(draws$dpars, mu / gamma(a))
  # see Jawitz 2004: Moments of truncated continuous univariate distributions
  m1 <- with(draws$dpars,
    scale * (incgamma(a, (ub / scale)^shape) - 
             incgamma(a, (lb / scale)^shape))
  )
  with(draws$dpars,
    m1 / (pweibull(ub, shape, scale = scale) - 
          pweibull(lb, shape, scale = scale))
  )
}

pp_expect_trunc_binomial <- function(draws, lb, ub) {
  lb <- ifelse(lb < -1, -1, lb)
  max_value <- max(draws$data$trials)
  ub <- ifelse(ub > max_value, max_value, ub)
  trials <- draws$data$trials
  if (length(trials) > 1) {
    trials <- as_draws_matrix(trials, dim_mu(draws))
  }
  args <- list(size = trials, prob = draws$dpars$mu)
  pp_expect_trunc_discrete(dist = "binom", args = args, lb = lb, ub = ub)
}

pp_expect_trunc_poisson <- function(draws, lb, ub) {
  lb <- ifelse(lb < -1, -1, lb)
  max_value <- 3 * max(draws$dpars$mu)
  ub <- ifelse(ub > max_value, max_value, ub)
  args <- list(lambda = draws$dpars$mu)
  pp_expect_trunc_discrete(dist = "pois", args = args, lb = lb, ub = ub)
}

pp_expect_trunc_negbinomial <- function(draws, lb, ub) {
  lb <- ifelse(lb < -1, -1, lb)
  max_value <- 3 * max(draws$dpars$mu)
  ub <- ifelse(ub > max_value, max_value, ub)
  args <- list(mu = draws$dpars$mu, size = draws$dpars$shape)
  pp_expect_trunc_discrete(dist = "nbinom", args = args, lb = lb, ub = ub)
}

pp_expect_trunc_geometric <- function(draws, lb, ub) {
  lb <- ifelse(lb < -1, -1, lb)
  max_value <- 3 * max(draws$dpars$mu)
  ub <- ifelse(ub > max_value, max_value, ub)
  args <- list(mu = draws$dpars$mu, size = 1)
  pp_expect_trunc_discrete(dist = "nbinom", args = args, lb = lb, ub = ub)
}

# pp_expect values for truncated discrete distributions
pp_expect_trunc_discrete <- function(dist, args, lb, ub) {
  stopifnot(is.matrix(lb), is.matrix(ub))
  message(
    "Computing pp_expect values for truncated ", 
    "discrete models may take a while."
  )
  pdf <- get(paste0("d", dist), mode = "function")
  cdf <- get(paste0("p", dist), mode = "function")
  mean_kernel <- function(x, args) {
    # just x * density(x)
    x * do_call(pdf, c(x, args))
  }
  if (any(is.infinite(c(lb, ub)))) {
    stop("lb and ub must be finite")
  }
  # simplify lb and ub back to vector format 
  vec_lb <- lb[1, ]
  vec_ub <- ub[1, ]
  min_lb <- min(vec_lb)
  # array of dimension S x N x length((lb+1):ub)
  mk <- lapply((min_lb + 1):max(vec_ub), mean_kernel, args = args)
  mk <- do_call(abind, c(mk, along = 3))
  m1 <- vector("list", ncol(mk))
  for (n in seq_along(m1)) {
    # summarize only over non-truncated values for this observation
    J <- (vec_lb[n] - min_lb + 1):(vec_ub[n] - min_lb)
    m1[[n]] <- rowSums(mk[, n, ][, J, drop = FALSE])
  }
  rm(mk)
  m1 <- do_call(cbind, m1)
  m1 / (do_call(cdf, c(list(ub), args)) - do_call(cdf, c(list(lb), args)))
}
