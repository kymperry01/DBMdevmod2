#' @title Predict temperature-based development of diamondback moth for multiple locations
#'
#' @description Predicts temperature-dependent development of diamondback
#' moth forward or reverse in time over multiple consecutive DBM lifestages and generations.
#' Analogous to \code{\link{fwdDev}} and \code{\link{revDev}} but designed to enable
#' simultaneous predictions for multiple locations and provide output in a convenient format.
#'
#' @details Implements Briere's model equation 2 (Briere, 1999) for temperature-dependent
#' insect development. Takes a \code{data.frame} containing the starting model parameters for
#' each location, a \code{data.frame} with the insect development parameters, and a \code{list} of
#' temperature time series \code{data.frames}. For each location, the temperature time series data
#' are matched for modelling using a unique identifier (e.g. weather station code or similar).
#'
#' @param locsDf A \code{data.frame} with the parameters for each location. For each location,
#' the parameters must be held in separate variables named `site`, `station` (temperature data
#' series identifier), `startDate`, `startStage`, `startDev` and `gens`. Each location corresponds to
#' a df row. see \code{\link{fwdDev}} and \code{\link{revDev}}.
#' @param tempObsDfList A list of temperature time series \code{data.frames} for all
#' locations. The time series data should contain columns named `station` (time series data
#' identifier such as a weather station code), `datetime` (POSIX date/times) and `obs` (
#' temperature observations). See \code{\link{formatBOMstdata}} for details.
#' @param devParamsDf A dataframe containing the four insect development parameters for
#' Briere's model. The parameters `a`, `Tmin`, `Tmax` and `m` are held as separate variables
#' with the parameters for each lifestage on separate rows, with row names as character strings.
#' @param timedir The direction in time for modelling, as a character string. If timedir = "fwd",
#' \code{\link{fwdDev}} is called; if timedir = "rev", \code{\link{revDev}} is called.
#' @param timeInt The time interval of increments in minutes. Th default value = 12.
#' The model has not yet been tested with other time intervals.
#' @param output A character string specifying the output format. By default outputs predictions
#' for each increment (output = "increments"). Other options are to output phenological summaries for
#' "stages" or "generations".
#' @param ... Other arguments to pass to the function.

#' @return A list. Each element will be a \code{data.frame} with model predictions for each location.
#'
#' @import dplyr
#'
#' @examples
#' library(lubridate)
#' library(dplyr)
#' # make an example siteslist with details (function arguments) for 2 sites
#' # note, names(sitelist) must be a character string matching the site name for each element (df)
#'  site1 <- data_frame(station = 18012, site = "site1",
#'                      startDate = "2014-11-01", startStage = "st3", startDev = 0.5, gens = 2)
#'  site2 <- data_frame(station = 26100, site = "site2", startDate = "2014-11-15",
#'                      startStage = "st3", startDev = 0.75, gens = 2)
#'  sitesDf <- bind_rows(site1, site2)
#'
#'  # create an example list of two dataframes with hourly temperature observations for two sites.
#'  # Must be named with a unique identifier also found in `sitesDf`
#'  date <- sort(rep(seq(as.Date("2014-06-01"), (as.Date("2015-05-31")), by = "day"), times = 24))
#'  hour <- rep(0:23, time = length(date)/24)
#'  datetime <- ymd_hms(paste(date, hour), truncated = 2)
#'  obs <- runif(n = length(date), min = 0, max = 38)
#'  df1 <- data.frame(station = 18012, datetime, obs)
#'  df2 <- data.frame(station = 26100, datetime, obs)
#'  dfList <- list(`18012` = df1, `26100` = df2)
#'  str(dfList)
#'
#'  # example dataframe with insect development parameters for three lifestages
#'  devParams <- data.frame(st1 = c(0.0003592, 1.754, 35.08, 4.347),
#'                      st2 = c(0.00036, -2.9122, 32.4565, 60.5092),
#'                      st3 = c(0.0003592, 1.754, 35.08, 4.347))
#'  rownames(devParams) <- c("a", "Tmin", "Tmax", "m")
#'  devParams <- t.data.frame(devParams)
#'
#'  # Back-predict development and output all increments
#'  rdev <- mlocDev(locsDf = sitesDf, tempObsDfList = dfList, devParamsDf = devParams,
#'              timedir = "rev")
#'
#'  # With output as summary of lifestages
#'  rstages <- mlocDev(locsDf = sitesDf, tempObsDfList = dfList, devParamsDf = devParams,
#'              timedir = "rev", output = "stages")
#'
#'  # With output as summary of generations
#'  rgens <-  mlocDev(locsDf = sitesDf, tempObsDfList = dfList, devParamsDf = devParams,
#'              timedir = "rev", output = "generations")
#'
#' @export
mlocDev <- function(locsDf, tempObsDfList, devParamsDf, timedir = "fwd",
                    timeInt = 60, output = "increments", ...) {

  # error checks
  # ... check for unique sites in each row
  if (anyDuplicated(locsDf$site) > 0) {
    stop("There are duplicated values in the `site` variable in locsDf. \n
         Each row should contain the model inputs for a unique site location")
  }

  # ... check all `station` values in locsDf are matched with climate dataframes
  statNAs <- sum(!locsDf$station %in% names(tempObsDfList))
  if (statNAs > 0) {
    stop(paste(statNAs, "values for `locsDf$station` do not match the names \n
               of temperature data.frames in tempObsDfList"))
  }

  # set development model for specified time direction
  stopifnot(timedir %in% c("fwd", "rev"))
  if (timedir == "fwd") {dev <- dbmdev::fwdDev}
  if (timedir == "rev") {dev <- dbmdev::revDev}

  # run the model for each site
  spl <- split(locsDf, locsDf$site)
  res <- lapply(spl, function(x){

    df <- tempObsDfList[[as.character(x$station)]]
    out <- dev(tempObsDf = df,
               devParamsDf = devParamsDf,
               startDate = as.character(as.Date(x$startDate)),
               startStage = x$startStage,
               startDev = x$startDev,
               gens = x$gens,
               output = output) %>%
      bind_rows()
    site <- data.frame(site = rep(x$site, nrow(out)))
    bind_cols(site, out)
  })
  res
  }
