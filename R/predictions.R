# select prediction method, based on model-object
select_prediction_method <- function(fun, model, expanded_frame, ci.lvl, type, faminfo, ppd, terms, typical, ...) {
  # get link-inverse-function
  linv <- get_link_inverse(fun, model)

  if (fun == "svyglm") {
    # survey-objects -----
    fitfram <- get_predictions_svyglm(model, expanded_frame, ci.lvl, linv, ...)
  } else if (fun == "svyglm.nb") {
    # survey-glm.nb-objects -----
    fitfram <- get_predictions_svyglmnb(model, expanded_frame, ci.lvl, linv, ...)
  } else if (fun == "stanreg") {
    # stan-objects -----
    fitfram <- get_predictions_stanreg(model, expanded_frame, ci.lvl, type, faminfo, ppd, ...)
  } else if (fun == "coxph") {
    # coxph-objects -----
    fitfram <- get_predictions_coxph(model, expanded_frame, ci.lvl, ...)
  } else if (fun == "lrm") {
    # lrm-objects -----
    fitfram <- get_predictions_lrm(model, expanded_frame, ci.lvl, linv, ...)
  } else if (fun == "glmmTMB") {
    # glmmTMB-objects -----
    fitfram <- get_predictions_glmmTMB(model, expanded_frame, ci.lvl, linv, ...)
  } else if (fun %in% c("lmer", "nlmer", "glmer")) {
    # merMod-objects  -----
    fitfram <- get_predictions_merMod(model, expanded_frame, ci.lvl, linv, type, terms, typical, ...)
  } else if (fun == "gam") {
    # gam-objects -----
    fitfram <- get_predictions_gam(model, expanded_frame, ci.lvl, linv, ...)
  } else if (fun == "vgam") {
    # vgam-objects -----
    fitfram <- get_predictions_vgam(model, expanded_frame, ci.lvl, linv, ...)
  } else if (fun %in% c("lme", "gls", "plm")) {
    # lme-objects -----
    fitfram <- get_predictions_lme(model, expanded_frame, ci.lvl, linv, terms, typical, ...)
  } else if (fun == "gee") {
    # gee-objects -----
    fitfram <- get_predictions_gee(model, expanded_frame, linv, ...)
  } else if (fun == "polr") {
    # polr-objects -----
    fitfram <- get_predictions_polr(model, expanded_frame, linv, ...)
  } else if (fun %in% c("betareg", "truncreg", "zeroinfl", "hurdle")) {
    # betareg, truncreg, zeroinfl and hurdle-objects -----
    fitfram <- get_predictions_generic2(model, expanded_frame, fun, typical, terms, ...)
  } else if (fun %in% c("glm", "glm.nb")) {
    # glm-objects -----
    fitfram <- get_predictions_glm(model, expanded_frame, ci.lvl, linv, ...)
  } else if (fun == "lm") {
    # lm-objects -----
    fitfram <- get_predictions_lm(model, expanded_frame, ci.lvl, linv, ...)
  } else {
    # general-objects -----
    fitfram <- get_predictions_generic(model, expanded_frame, linv, ...)
  }

  fitfram
}


# predictions for survey objects ----

get_predictions_svyglm <- function(model, fitfram, ci.lvl, linv, ...) {
  # does user want standard errors?
  se <- !is.null(ci.lvl) && !is.na(ci.lvl)

  prdat <-
    stats::predict(
      model,
      newdata = fitfram,
      type = "link",
      se.fit = se,
      level = ci.lvl,
      ...
    )

  # check if user wants standard errors
  if (se) {
    # get variance matrix for standard errors. "survey" stores the information
    # somewhat different from classical predict function
    vv <- attr(prdat, "var")

    # compute standard errors
    if (is.matrix(vv))
      prdat <- as.data.frame(cbind(prdat, sqrt(diag(vv))))
    else
      prdat <- as.data.frame(cbind(prdat, sqrt(vv)))

    # consistent column names
    colnames(prdat) <- c("fit", "se.fit")

    # copy predictions
    fitfram$predicted <- linv(prdat$fit)

    # calculate CI
    fitfram$conf.low <- linv(prdat$fit - stats::qnorm(.975) * prdat$se.fit)
    fitfram$conf.high <- linv(prdat$fit + stats::qnorm(.975) * prdat$se.fit)
  } else {
    # copy predictions
    fitfram$predicted <- as.vector(prdat)

    # no CI
    fitfram$conf.low <- NA
    fitfram$conf.high <- NA
  }

  fitfram
}


# predictions for glm ----

get_predictions_glm <- function(model, fitfram, ci.lvl, linv, ...) {
  # does user want standard errors?
  se <- !is.null(ci.lvl) && !is.na(ci.lvl)

  prdat <-
    stats::predict.glm(
      model,
      newdata = fitfram,
      type = "link",
      se.fit = se,
      level = ci.lvl,
      ...
    )

  # copy predictions
  get_base_fitfram(fitfram, linv, prdat, se)
}


# predictions for polr ----

#' @importFrom tidyr gather
#' @importFrom dplyr bind_cols bind_rows
#' @importFrom tibble rownames_to_column
#' @importFrom rlang .data
get_predictions_polr <- function(model, fitfram, linv, ...) {
  prdat <-
    stats::predict(
      model,
      newdata = fitfram,
      type = "probs",
      ...
    )

  prdat <- as.data.frame(prdat)

  # usually, we have same numbers of rows for predictions and model frame.
  # this is, however. not true when calling the "emm()" function. in this
  # case. just return predictions
  if (nrow(prdat) > nrow(fitfram) && ncol(prdat) == 1) {
    colnames(prdat)[1] <- "predicted"
    return(tibble::rownames_to_column(prdat, var = "response.level"))
  }

  # bind predictions to model frame
  fitfram <- dplyr::bind_cols(prdat, fitfram)

  # for proportional ordinal logistic regression (see MASS::polr),
  # we have predicted values for each response category. Hence,
  # gather columns
  key_col <- "response.level"
  value_col <- "predicted"

  fitfram <- tidyr::gather(fitfram, !! key_col, !! value_col, !! 1:ncol(prdat))

  # No CI
  fitfram$conf.low <- NA
  fitfram$conf.high <- NA

  fitfram
}


# predictions for regression models w/o SE ----

get_predictions_generic2 <- function(model, fitfram, fun, typical, terms, ...) {
  # get prediction type.
  pt <- dplyr::case_when(
    fun %in% c("hurdle", "zeroinfl") ~ "response",
    TRUE ~ "response"
  )

  prdat <-
    stats::predict(
      model,
      newdata = fitfram,
      type = pt,
      ...
    )

  fitfram$predicted <- as.vector(prdat)

  # get standard errors from variance-covariance matrix
  se.pred <-
    get_se_from_vcov(
      model = model,
      fitfram = fitfram,
      typical = typical,
      terms = terms,
      fun = fun
    )

  se.fit <- se.pred$se.fit
  fitfram <- se.pred$fitfram

  # CI
  fitfram$conf.low <- fitfram$predicted - stats::qnorm(.975) * se.fit
  fitfram$conf.high <- fitfram$predicted + stats::qnorm(.975) * se.fit

  fitfram
}


# predictions for lrm ----

#' @importFrom stats plogis qnorm
get_predictions_lrm <- function(model, fitfram, ci.lvl, linv, ...) {
  # does user want standard errors?
  se <- !is.null(ci.lvl) && !is.na(ci.lvl)

  prdat <-
    stats::predict(
      model,
      newdata = fitfram,
      type = "lp",
      se.fit = se,
      ...
    )

  # copy predictions
  fitfram$predicted <- stats::plogis(prdat$linear.predictors)

  # did user request standard errors? if yes, compute CI
  if (se) {
    # calculate CI
    fitfram$conf.low <- stats::plogis(prdat$linear.predictors - stats::qnorm(.975) * prdat$se.fit)
    fitfram$conf.high <- stats::plogis(prdat$linear.predictors + stats::qnorm(.975) * prdat$se.fit)
  } else {
    # No CI
    fitfram$conf.low <- NA
    fitfram$conf.high <- NA
  }

  fitfram
}


# predictions for svyglm.nb ----

get_predictions_svyglmnb <- function(model, fitfram, ci.lvl, linv, ...) {
  # does user want standard errors?
  se <- !is.null(ci.lvl) && !is.na(ci.lvl)

  prdat <-
    stats::predict(
      model,
      newdata = fitfram,
      type = "link",
      se.fit = se,
      level = ci.lvl,
      ...
    )

  # copy predictions
  get_base_fitfram(fitfram, linv, prdat, se)
}


# predictions for glmmTMB ----

#' @importFrom stats family
get_predictions_glmmTMB <- function(model, fitfram, ci.lvl, linv, ...) {
  # does user want standard errors?
  se <- !is.null(ci.lvl) && !is.na(ci.lvl)

  prdat <- stats::predict(
    model,
    newdata = fitfram,
    zitype = "response",
    type = "response",
    se.fit = se,
    ...
  )

  # did user request standard errors? if yes, compute CI
  if (se) {
    fitfram$predicted <- prdat$fit

    # see http://www.biorxiv.org/content/biorxiv/suppl/2017/05/01/132753.DC1/132753-2.pdf
    # page 7

    # calculate CI
    fitfram$conf.low <- prdat$fit - stats::qnorm(.975) * prdat$se.fit
    fitfram$conf.high <- prdat$fit + stats::qnorm(.975) * prdat$se.fit
  } else {
    # copy predictions
    fitfram$predicted <- as.vector(prdat)

    # no CI
    fitfram$conf.low <- NA
    fitfram$conf.high <- NA
  }

  fitfram
}


# predictions for merMod ----

get_predictions_merMod <- function(model, fitfram, ci.lvl, linv, type, terms, typical, ...) {
  # does user want standard errors?
  se <- !is.null(ci.lvl) && !is.na(ci.lvl)

  # check whether predictions should be conditioned
  # on random effects (grouping level) or not.
  if (type == "fe")
    ref <- NA
  else
    ref <- NULL


  fitfram$predicted <- stats::predict(
    model,
    newdata = fitfram,
    type = "response",
    re.form = ref,
    ...
  )

  if (se) {
    # get standard errors from variance-covariance matrix
    se.pred <-
      get_se_from_vcov(
        model = model,
        fitfram = fitfram,
        typical = typical,
        terms = terms
      )

    se.fit <- se.pred$se.fit
    fitfram <- se.pred$fitfram

    if (is.null(linv)) {
      # calculate CI for linear mixed models
      fitfram$conf.low <- fitfram$predicted - stats::qnorm(.975) * se.fit
      fitfram$conf.high <- fitfram$predicted + stats::qnorm(.975) * se.fit
    } else {
      # get link-function and back-transform fitted values
      # to original scale, so we compute proper CI
      lf <- get_link_fun(model)

      # calculate CI for glmm
      fitfram$conf.low <- linv(lf(fitfram$predicted) - stats::qnorm(.975) * se.fit)
      fitfram$conf.high <- linv(lf(fitfram$predicted) + stats::qnorm(.975) * se.fit)
    }

    # tell user
    message("Note: uncertainty of the random effects parameters are not taken into account for confidence intervals.")
  } else {
    # no SE and CI for lme4-predictions
    fitfram$conf.low <- NA
    fitfram$conf.high <- NA
  }

  fitfram
}



# predictions for stanreg ----

#' @importFrom tibble as_tibble
#' @importFrom sjstats hdi resp_var
#' @importFrom sjmisc rotate_df
#' @importFrom purrr map_dbl map_df
#' @importFrom dplyr bind_cols
#' @importFrom stats median
get_predictions_stanreg <- function(model, fitfram, ci.lvl, type, faminfo, ppd, ...) {
  # check if pkg is available
  if (!requireNamespace("rstanarm", quietly = TRUE)) {
    stop("Package `rstanarm` is required to compute predictions.", call. = F)
  }

  # does user want standard errors?
  se <- !is.null(ci.lvl) && !is.na(ci.lvl)

  # check whether predictions should be conditioned
  # on random effects (grouping level) or not.
  if (inherits(model, "lmerMod") && type != "fe")
    ref <- NULL
  else
    ref <- NA

  # compute posterior predictions
  if (ppd) {
    # for binomial models, "newdata" also needs a response
    # value. we take the value for a successful event
    if (faminfo$is_bin) {
      resp.name <- sjstats::resp_var(model)
      # successfull events
      fitfram[[resp.name]] <- factor(1)
    }

    prdat <- rstanarm::posterior_predict(
      model,
      newdata = fitfram,
      re.form = ref,
      ...
    )
  } else {
    # get posterior distribution of the linear predictor
    # note that these are not best practice for inferences,
    # because they don't take the uncertainty of the Sd into account
    prdat <- rstanarm::posterior_linpred(
      model,
      newdata = fitfram,
      transform = TRUE,
      re.form = ref,
      ...
    )

    # tell user
    message("Note: uncertainty of error terms are not taken into account. You may want to use `rstanarm::posterior_predict()`.")
  }

  # we have a list of 4000 samples, so we need to coerce to data frame
  prdat <- tibble::as_tibble(prdat)

  # for models with binomial outcome, we just have 0 and 1 as predictions
  # so we need to
  if (faminfo$family != "gaussian" && ppd) {
    # compute median, as "most probable estimate"
    fitfram$predicted <- purrr::map_dbl(prdat, mean)

    # can't compute SE, because we would need many replicates
    # of the posterior predicted distribution
    se <- FALSE
    message("For non-gaussian models and if `ppd = TRUE`, no confidence intervals are calculated.")
  } else {
    # compute median, as "most probable estimate"
    fitfram$predicted <- purrr::map_dbl(prdat, stats::median)

    # compute HDI, as alternative to CI
    hdi <- prdat %>%
      purrr::map_df(~ sjstats::hdi(.x, prob = ci.lvl)) %>%
      sjmisc::rotate_df()
  }

  if (se) {
    # bind HDI
    fitfram$conf.low <- hdi[[1]]
    fitfram$conf.high <- hdi[[2]]
  } else {
    # no CI
    fitfram$conf.low <- NA
    fitfram$conf.high <- NA
  }

  fitfram
}


# predictions for coxph ----

#' @importFrom prediction prediction
get_predictions_coxph <- function(model, fitfram, ci.lvl, ...) {
  # does user want standard errors?
  se <- !is.null(ci.lvl) && !is.na(ci.lvl)

  prdat <-
    stats::predict(
      model,
      newdata = fitfram,
      type = "lp",
      se.fit = se,
      ...
    )

  # did user request standard errors? if yes, compute CI
  if (se) {
    # copy predictions
    fitfram$predicted <- exp(prdat$fit)

    # calculate CI
    fitfram$conf.low <- exp(prdat$fit - stats::qnorm(.975) * prdat$se.fit)
    fitfram$conf.high <- exp(prdat$fit + stats::qnorm(.975) * prdat$se.fit)
  } else {
    # copy predictions
    fitfram$predicted <- exp(as.vector(prdat))

    # no CI
    fitfram$conf.low <- NA
    fitfram$conf.high <- NA
  }

  fitfram
}



# predictions for gam ----

#' @importFrom prediction prediction
get_predictions_gam <- function(model, fitfram, ci.lvl, ...) {
  # No standard errors (currently) for gam predictions with newdata
  # se <- !is.null(ci.lvl) && !is.na(ci.lvl)
  se <- FALSE

  prdat <-
    stats::predict(
      model,
      newdata = fitfram,
      type = "response",
      se.fit = se,
      ...
    )

  # did user request standard errors? if yes, compute CI
  if (se) {
    # copy predictions
    fitfram$predicted <- prdat$fit

    # calculate CI
    fitfram$conf.low <- prdat$fit - stats::qnorm(.975) * prdat$se.fit
    fitfram$conf.high <- prdat$fit + stats::qnorm(.975) * prdat$se.fit
  } else {
    # copy predictions
    fitfram$predicted <- as.vector(prdat)

    # no CI
    fitfram$conf.low <- NA
    fitfram$conf.high <- NA
  }

  fitfram
}


# predictions for vgam ----

#' @importFrom prediction prediction
get_predictions_vgam <- function(model, fitfram, ci.lvl, linv, ...) {
  prdat <- stats::predict(
    model,
    type = "response",
    ...
  )

  # copy predictions
  fitfram$predicted <- prdat$fitted

  fitfram
}


# predictions for lm ----

get_predictions_lm <- function(model, fitfram, ci.lvl, linv, ...) {
  # does user want standard errors?
  se <- !is.null(ci.lvl) && !is.na(ci.lvl)

  prdat <-
    stats::predict(
      model,
      newdata = fitfram,
      type = "response",
      se.fit = se,
      level = ci.lvl,
      ...
    )

  # did user request standard errors? if yes, compute CI
  if (se) {
    # copy predictions
    fitfram$predicted <- prdat$fit

    # calculate CI
    fitfram$conf.low <- prdat$fit - stats::qnorm(.975) * prdat$se.fit
    fitfram$conf.high <- prdat$fit + stats::qnorm(.975) * prdat$se.fit
  } else {
    # copy predictions
    fitfram$predicted <- as.vector(prdat)

    # no CI
    fitfram$conf.low <- NA
    fitfram$conf.high <- NA
  }

  fitfram
}


# predictions for lme ----

#' @importFrom stats model.matrix formula vcov
#' @importFrom sjstats resp_var pred_vars
#' @importFrom purrr map
#' @importFrom tibble add_column
get_predictions_lme <- function(model, fitfram, ci.lvl, linv, terms, typical, ...) {
  # does user want standard errors?
  se <- !is.null(ci.lvl) && !is.na(ci.lvl)

  prdat <-
    stats::predict(
      model,
      newdata = fitfram,
      type = "response",
      level = 0,
      ...
    )

  # copy predictions
  fitfram$predicted <- as.vector(prdat)

  # did user request standard errors? if yes, compute CI
  if (se) {
    se.pred <- get_se_from_vcov(model = model, fitfram = fitfram, typical = typical, terms = terms)

    se.fit <- se.pred$se.fit
    fitfram <- se.pred$fitfram

    # calculate CI
    fitfram$conf.low <- fitfram$predicted - stats::qnorm(.975) * se.fit
    fitfram$conf.high <- fitfram$predicted + stats::qnorm(.975) * se.fit

    # tell user
    message("Note: uncertainty of the random effects parameters are not taken into account for confidence intervals.")
  } else {
    # No CI
    fitfram$conf.low <- NA
    fitfram$conf.high <- NA
  }

  fitfram
}


# predictions for gee ----

get_predictions_gee <- function(model, fitfram, linv, ...) {
  prdat <-
    stats::predict(
      model,
      type = "response",
      ...
    )
  # copy predictions
  fitfram$predicted <- as.vector(prdat)

  # No CI
  fitfram$conf.low <- NA
  fitfram$conf.high <- NA

  fitfram
}


# predictions for generic models ----

#' @importFrom prediction prediction
#' @importFrom tibble as_tibble
#' @importFrom sjmisc var_rename
get_predictions_generic <- function(model, fitfram, linv, ...) {
  prdat <-
    prediction::prediction(
      model,
      data = fitfram,
      type = "response",
      ...
    )

  # copy predictions
  fitfram$predicted <- prdat$fitted

  # No CI
  fitfram$conf.low <- NA
  fitfram$conf.high <- NA

  fitfram
}


get_base_fitfram <- function(fitfram, linv, prdat, se) {
  # copy predictions
  if (typeof(prdat) == "double")
    fitfram$predicted <- linv(prdat)
  else
    fitfram$predicted <- linv(prdat$fit)

  # did user request standard errors? if yes, compute CI
  if (se) {
    # calculate CI
    fitfram$conf.low <- linv(prdat$fit - stats::qnorm(.975) * prdat$se.fit)
    fitfram$conf.high <- linv(prdat$fit + stats::qnorm(.975) * prdat$se.fit)
  } else {
    # No CI
    fitfram$conf.low <- NA
    fitfram$conf.high <- NA
  }

  fitfram
}



# get standard errors of predictions from model matrix and vcov ----

#' @importFrom tibble add_column
#' @importFrom stats model.matrix terms vcov
#' @importFrom dplyr arrange_
#' @importFrom sjstats resp_var
get_se_from_vcov <- function(model, fitfram, typical, terms, fun = NULL) {
  # copy data frame with predictions
  newdata <- get_expanded_data(
    model,
    get_model_frame(model, fe.only = FALSE),
    terms,
    typ.fun = typical,
    fac.typical = FALSE
  )

  # add response
  newdata <- tibble::add_column(newdata, response.val = 0)

  # proper column names, needed for getting model matrix
  colnames(newdata)[ncol(newdata)] <- sjstats::resp_var(model)


  # sort data by grouping levels, so we have the correct order
  # to slice data afterwards
  if (length(terms) > 2) {
    newdata <- dplyr::arrange_(newdata, terms[3])
    fitfram <- dplyr::arrange_(fitfram, terms[3])
  }

  if (length(terms) > 1) {
    newdata <- dplyr::arrange_(newdata, terms[2])
    fitfram <- dplyr::arrange_(fitfram, terms[2])
  }

  newdata <- dplyr::arrange_(newdata, terms[1])
  fitfram <- dplyr::arrange_(fitfram, terms[1])


  # get variance-covariance-matrix, depending on model type
  if (is.null(fun))
    vcm <- as.matrix(stats::vcov(model))
  else if (fun %in% c("hurdle", "zeroinfl"))
    vcm <- as.matrix(stats::vcov(model, model = "count"))
  else if (fun == "betareg")
    vcm <- as.matrix(stats::vcov(model, model = "mean"))
  else if (fun == "truncreg") {
    vcm <- as.matrix(stats::vcov(model))
    # remove sigma from matrix
    vcm <- vcm[1:(nrow(vcm) - 1), 1:(ncol(vcm) - 1)]
  } else
    vcm <- as.matrix(stats::vcov(model))


  # code to compute se of prediction taken from
  # http://bbolker.github.io/mixedmodels-misc/glmmFAQ.html#predictions-andor-confidence-or-prediction-intervals-on-predictions
  mm <- stats::model.matrix(stats::terms(model), newdata)
  pvar <- diag(mm %*% vcm %*% t(mm))
  se.fit <- sqrt(pvar)

  # shorten to length of fitfram
  se.fit <- se.fit[1:nrow(fitfram)]

  list(fitfram = fitfram, se.fit = se.fit)
}
