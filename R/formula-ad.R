#' Additional Response Information
#' 
#' Provide additional information on the response variable 
#' in \pkg{brms} models, such as censoring, truncation, or
#' known measurement error.
#' 
#' @name addition-terms
#' 
#' @param x A vector; usually a variable defined in the data. Allowed values
#'   depend on the function: \code{resp_se} and \code{resp_weights} require
#'   positive numeric values. \code{resp_trials}, \code{resp_thres}, and
#'   \code{resp_cat} require positive integers. \code{resp_dec} requires
#'   \code{0} and \code{1}, or alternatively \code{'lower'} and \code{'upper'}.
#'   \code{resp_subset} requires \code{0} and \code{1}, or alternatively
#'   \code{FALSE} and \code{TRUE}. \code{resp_cens} requires \code{'left'},
#'   \code{'none'}, \code{'right'}, and \code{'interval'} (or equivalently
#'   \code{-1}, \code{0}, \code{1}, and \code{2}) to indicate left, no, right,
#'   or interval censoring.
#' @param sigma Logical; Indicates whether the residual standard deviation
#'  parameter \code{sigma} should be included in addition to the known
#'  measurement error. Defaults to \code{FALSE} for backwards compatibility,
#'  but setting it to \code{TRUE} is usually the better choice.
#' @param scale Logical; Indicates whether weights should be scaled
#'  so that the average weight equals one. Defaults to \code{FALSE}.
#' @param y2 A vector specifying the upper bounds in interval censoring.
#'  Will be ignored for non-interval censored observations. However, it 
#'  should NOT be \code{NA} even for non-interval censored observations to
#'  avoid accidental exclusion of these observations.
#' @param lb A numeric vector or single numeric value specifying 
#'   the lower truncation bound.
#' @param ub A numeric vector or single numeric value specifying 
#'   the upper truncation bound.
#' @param sdy Optional known measurement error of the response
#'   treated as standard deviation. If specified, handles
#'   measurement error and (completely) missing values
#'   at the same time using the plausible-values-technique.
#' @param denom A vector of positive numeric values specifying
#'   the denominator values from which the response rates are computed.
#' @param gr A vector of grouping indicators.
#' @param ... For \code{resp_vreal}, vectors of real values. 
#'   For \code{resp_vint}, vectors of integer values.  
#'
#' @return A list of additional response information to be processed further
#'   by \pkg{brms}.
#'
#' @details 
#'   These functions are almost solely useful when
#'   called in formulas passed to the \pkg{brms} package.
#'   Within formulas, the \code{resp_} prefix may be omitted.
#'   More information is given in the 'Details' section
#'   of \code{\link{brmsformula}}.
#'   
#' @seealso 
#'   \code{\link{brm}}, 
#'   \code{\link{brmsformula}}   
#'  
#' @examples 
#' \dontrun{
#' ## Random effects meta-analysis
#' nstudies <- 20
#' true_effects <- rnorm(nstudies, 0.5, 0.2)
#' sei <- runif(nstudies, 0.05, 0.3)
#' outcomes <- rnorm(nstudies, true_effects, sei)
#' data1 <- data.frame(outcomes, sei)
#' fit1 <- brm(outcomes | se(sei, sigma = TRUE) ~ 1,
#'             data = data1)
#' summary(fit1)
#' 
#' ## Probit regression using the binomial family
#' n <- sample(1:10, 100, TRUE)  # number of trials
#' success <- rbinom(100, size = n, prob = 0.4)
#' x <- rnorm(100)
#' data2 <- data.frame(n, success, x)
#' fit2 <- brm(success | trials(n) ~ x, data = data2,
#'             family = binomial("probit"))
#' summary(fit2)
#' 
#' ## Survival regression modeling the time between the first 
#' ## and second recurrence of an infection in kidney patients.
#' fit3 <- brm(time | cens(censored) ~ age * sex + disease + (1|patient), 
#'             data = kidney, family = lognormal())
#' summary(fit3)
#' 
#' ## Poisson model with truncated counts  
#' fit4 <- brm(count | trunc(ub = 104) ~ zBase * Trt, 
#'             data = epilepsy, family = poisson())
#' summary(fit4)
#' }
#'   
NULL

#' @rdname addition-terms
#' @export
resp_se <- function(x, sigma = FALSE) {
  se <- deparse(substitute(x))
  sigma <- as_one_logical(sigma)
  class_resp_special(
    "se", call = match.call(),
    vars = nlist(se), flags = nlist(sigma)
  )
}

#' @rdname addition-terms
#' @export
resp_weights <- function(x, scale = FALSE) {
  weights <- deparse(substitute(x))
  scale <- as_one_logical(scale)
  class_resp_special(
    "weights", call = match.call(),
    vars = nlist(weights), flags = nlist(scale)
  )
}

#' @rdname addition-terms
#' @export
resp_trials <- function(x) {
  trials <- deparse(substitute(x))
  class_resp_special("trials", call = match.call(), vars = nlist(trials))
}

#' @rdname addition-terms
#' @export
resp_thres <- function(x, gr = NA) {
  thres <- deparse(substitute(x))
  gr <- deparse(substitute(gr))
  class_resp_special("thres", call = match.call(), vars = nlist(thres, gr))
}

#' @rdname addition-terms
#' @export
resp_cat <- function(x) {
  # deprecated as of brms 2.10.5
  # number of thresholds = number of response categories - 1
  thres <- deparse(substitute(x))
  str_add(thres) <- " - 1"
  class_resp_special(
    "thres", call = match.call(), 
    vars = nlist(thres, gr = "NA")
  )
}

#' @rdname addition-terms
#' @export
resp_dec <- function(x) {
  dec <- deparse(substitute(x))
  class_resp_special("dec", call = match.call(), vars = nlist(dec))
}

#' @rdname addition-terms
#' @export
resp_cens <- function(x, y2 = NA) {
  cens <- deparse(substitute(x))
  y2 <- deparse(substitute(y2))
  class_resp_special("cens", call = match.call(), vars = nlist(cens, y2))
}

#' @rdname addition-terms
#' @export
resp_trunc <- function(lb = -Inf, ub = Inf) {
  lb <- deparse(substitute(lb))
  ub <- deparse(substitute(ub))
  class_resp_special("trunc", call = match.call(), vars = nlist(lb, ub))
}

#' @rdname addition-terms
#' @export
resp_mi <- function(sdy = NA) {
  sdy <- deparse(substitute(sdy))
  class_resp_special("mi", call = match.call(), vars = nlist(sdy))
}

#' @rdname addition-terms
#' @export
resp_rate <- function(denom) {
  denom <- deparse(substitute(denom))
  class_resp_special("rate", call = match.call(), vars = nlist(denom))
}

#' @rdname addition-terms
#' @export
resp_subset <- function(x) {
  subset <- deparse(substitute(x))
  class_resp_special("subset", call = match.call(), vars = nlist(subset))
}

#' @rdname addition-terms
#' @export
resp_vreal <- function(...) {
  vars <- as.list(substitute(list(...)))[-1]
  class_resp_special("vreal", call = match.call(), vars = vars)
}

#' @rdname addition-terms
#' @export
resp_vint <- function(...) {
  vars <- as.list(substitute(list(...)))[-1]
  class_resp_special("vint", call = match.call(), vars = vars)
}

# class underlying response addition terms
# @param type type of the addition term
# @param call the call to the original addition term function
# @param vars named list of unevaluated variables
# @param flags named list of (evaluated) logical indicators
class_resp_special <- function(type, call, vars = list(), flags = list()) {
  type <- as_one_character(type)
  stopifnot(is.call(call), is.list(vars), is.list(flags))
  label <- deparse(call)
  out <- nlist(type, call, label, vars, flags)
  class(out) <- c("resp_special")
  out
}

# computes data for addition arguments
eval_rhs <- function(formula, data = NULL) {
  formula <- as.formula(formula)
  eval(rhs(formula)[[2]], data, environment(formula))
}

# get expression for a variable of an addition term
# @param x list with potentail $adforms elements
# @param ad name of the addition term
# @param target name of the element to extract
# @type type of the element to extract
# @return a character string or NULL
get_ad_expr <- function(x, ad, name, type = "vars") {
  ad <- as_one_character(ad)
  name <- as_one_character(name)
  type <- as_one_character(type)
  if (is.null(x$adforms[[ad]])) {
    return(NULL)
  }
  out <- eval_rhs(x$adforms[[ad]])[[type]][[name]]
  if (type == "vars" && is_equal(out, "NA")) {
    out <- NULL
  }
  out
}

# get values of a variable used in an addition term
# @return a vector of values or NULL
get_ad_values <- function(x, ad, name, data) {
  expr <- get_ad_expr(x, ad, name, type = "vars")
  eval2(expr, data)
}

# get a flag used in an addition term
# @return TRUE or FALSE
get_ad_flag <- function(x, ad, name) {
  expr <- get_ad_expr(x, ad, name, type = "flags")
  as_one_logical(eval2(expr))
}

# get variable names used in addition terms
get_ad_vars <- function(x, ...) {
  UseMethod("get_ad_vars")
}

#' @export
get_ad_vars.brmsterms <- function(x, ad, ...) {
  ad <- as_one_character(ad)
  all_vars(x$adforms[[ad]])
}

#' @export
get_ad_vars.mvbrmsterms <- function(x, ad, ...) {
  unique(ulapply(x$terms, get_ad_vars, ad = ad, ...))
}

# coerce censored values into the right format
# @param x vector of censoring indicators
# @return transformed vector of censoring indicators
prepare_cens <- function(x) {
  .prepare_cens <- function(x) {  
    stopifnot(length(x) == 1L)
    regx <- paste0("^", x)
    if (grepl(regx, "left")) {
      x <- -1
    } else if (grepl(regx, "none") || isFALSE(x)) {
      x <- 0
    } else if (grepl(regx, "right") || isTRUE(x)) {
      x <- 1
    } else if (grepl(regx, "interval")) {
      x <- 2
    }
    return(x)
  }
  x <- unname(x)
  if (is.factor(x)) {
    x <- as.character(x)
  }
  ulapply(x, .prepare_cens)
}

# extract information on censoring of the response variable
# @param x a brmsfit object
# @param resp optional names of response variables for which to extract values
# @return vector of censoring indicators or NULL in case of no censoring
get_cens <- function(x, resp = NULL, newdata = NULL) {
  stopifnot(is.brmsfit(x))
  resp <- validate_resp(resp, x, multiple = FALSE)
  bterms <- brmsterms(x$formula)
  if (!is.null(resp)) {
    bterms <- bterms$terms[[resp]]
  }
  if (is.null(newdata)) {
    newdata <- model.frame(x)
  }
  out <- NULL
  if (is.formula(bterms$adforms$cens)) {
    out <- get_ad_values(bterms, "cens", "cens", newdata)
    out <- prepare_cens(out)
  }
  out
}

# extract truncation boundaries
trunc_bounds <- function(x, ...) {
  UseMethod("trunc_bounds")
}

# @return a named list with one element per response variable
#' @export
trunc_bounds.mvbrmsterms <- function(x, ...) {
  lapply(x$terms, trunc_bounds, ...)
}

# @param data data.frame containing the truncation variables
# @param incl_family include the family in the derivation of the bounds?
# @param stan return bounds in form of Stan syntax?
# @return a list with elements 'lb' and 'ub'
#' @export
trunc_bounds.brmsterms <- function(x, data = NULL, incl_family = FALSE, 
                                   stan = FALSE, ...) {
  if (is.formula(x$adforms$trunc)) {
    trunc <- eval_rhs(x$adforms$trunc)
  } else {
    trunc <- resp_trunc()
  }
  out <- list(
    lb = eval2(trunc$vars$lb, data),
    ub = eval2(trunc$vars$ub, data)
  )
  if (incl_family) {
    family_bounds <- family_bounds(x)
    out$lb <- max(out$lb, family_bounds$lb)
    out$ub <- min(out$ub, family_bounds$ub)
  }
  if (stan) {
    if (any(out$lb > -Inf | out$ub < Inf)) {
      tmp <- c(
        if (out$lb > -Inf) paste0("lower=", out$lb),
        if (out$ub < Inf) paste0("upper=", out$ub)
      )
      out <- paste0("<", paste0(tmp, collapse = ","), ">")
    } else {
      out <- ""
    }
  }
  out
}

# check if addition argument 'subset' ist used in the model
has_subset <- function(bterms) {
  .has_subset <- function(x) {
    is.formula(x$adforms$subset)
  }
  if (is.brmsterms(bterms)) {
    out <- .has_subset(bterms)
  } else if (is.mvbrmsterms(bterms)) {
    out <- any(ulapply(bterms$terms, .has_subset))
  } else {
    out <- FALSE
  }
  out 
}
