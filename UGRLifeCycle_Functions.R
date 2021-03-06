library(VGAM) # postive only normal distribution function

###########################################################
##########   DISTRIBUTION FUNCTIONS     ###################
###########################################################

#--------------BETA DISTRIBUTIONS----------------#
# Estimates shape parameters for a beta distribution based on mean and stdev
# Used to keep survival and transition probabilityes from 0 to 1
# Used in bev_holt and move function
# returns a single random draw from a beta distribution
# note, this returns 0.5 if the stdev input is a 0, so bev-holt function defaults to norm if stdev = 0
get_random_beta <- function(mean, stdev) {
    # turn the standard deviation into a variance
    var <- stdev^2
    alpha <- ((1 - mean) / var - 1 / mean) * mean ^ 2
    beta <- alpha * (1 / mean - 1)
    # get the random draw from beta distribution
    # use error handling incase the rbeta bombs
    random_beta_draw <- tryCatch({
        rbeta(1, alpha, beta)
    }, error = function(e) {
        mean
    }, warning = function(w) {
        mean
    })
    return(random_beta_draw)
}


#--------------LOG-NORMAL DISTRIBUTIONS----------------#
# Estimates shape parameters for log-normal distribution based on mean and standard deviation
# Used to used in bev-holt for capacity stochasticity
# returns a single random draw from a log-normal distribution
get_random_log <- function(mean, stdev) {
    location <- log(mean^2 / sqrt(stdev^2 + mean^2))
    shape <- sqrt(log(1 + (stdev^2 / mean^2)))
    random_log_draw <- rlnorm(1, location, shape)
    return(random_log_draw)
}

###########################################################
##########   MOVEMENT STOCHASTICITY     ###################
###########################################################
# Allows stochastic estimate of choice with two outcomes
# Takes parameter array for first choice
# Outputs a list containing the probability of each choice
# became move_choices to be more explicit, update
life_history_choices <- function(params) {
    # if no stochasticity
    if (stochasticity == "OFF") {
        # just set to first choice parameter
        prob1 <- params$life_history
    } else {
        # beta distribution for first choice
        prob1 <- get_random_beta(params$life_history, params$life_history_sd)   
    }
    prob2 <- 1 - prob1
    life_history_probs <- list(prob1 = prob1, prob2 = prob2)
    return(life_history_probs)
}


###########################################################
##########   BEAVERTON HOLT FUNCTIONS   ###################
###########################################################
# Take two parameters
# stage1 = population at start life stage
# stage_param = array of productivity, capacity, and stdeviations
# returns stage 2 = population size at next life stage
#--------------BEAVERTON HOLT----------------#
bev_holt <- function (origin = 'NO', stage1_pop, params) {
    # First set natural or hatchery scaler
    if (origin == 'NO') {
        prod_scaler <- params$natural_prod_scaler
        cap_scaler <- params$natural_cap_scaler
    } else {
        prod_scaler <- params$hatchery_prod_scaler
        cap_scaler <- params$hatchery_cap_scaler
    }
    
    # Use stochasticity estimates on parameters
    if (is.na(params$fit_sd)) {
        # set productivity for survival with beta dist
        if (params$productivity < 1 & params$productivity_sd > 0 ) {
            # using beta distribution
            prod <- get_random_beta(params$productivity, params$productivity_sd)
            # multiply by the productivity scaler
            prod <- prod * prod_scaler
            # be sure it isn't > 1
            if (prod > 1) {
                prod <- 1
            }
        # or set productivity for fecundity
        # or for survival with no stochasticity
        } else if (params$productivity >= 1 | params$productivity_sd == 0) {
            # using positive normal distribution
            prod <- rposnorm(1, params$productivity, params$productivity_sd)
            # scale it
            prod <- prod * prod_scaler
        }
        # set capacity using log-normal distribution function
        cap <- get_random_log(params$capacity, params$capacity_sd)
        # scale it
        cap <- cap * cap_scaler
        # and finally bev-holt estimate
        stage2_pop = (stage1_pop / (((1/prod) + ((1/cap)*stage1_pop))))
        return(floor(stage2_pop))
        
    # Use stochasticity on model fit, note - this should only be used on survival, not fecundity
    } else if (!is.na(params$fit_sd)) {
        # multiply by the productivity scaler
        prod <- params$productivity * prod_scaler
        # check if survival
        if (params$productivity < 1) {
            # and after scaliing is it > 1
            if (prod > 1) {
                prod <- 1
            }
        }
        # scale capacity
        cap <- params$capacity * cap_scaler
        # implement the bev-holt
        stage2_pop = (stage1_pop / (((1/prod) + ((1/cap)*stage1_pop))))
        # set error
        sd <- rnorm(1, 0, params$fit_sd)
        # and get the final estimate
        stage2_pop <- stage2_pop*exp(sd)
        # double check this didn't produce more fish than we started with
        if (stage2_pop > stage1_pop) {
            return(stage1_pop)
        } else {
            return(floor(stage2_pop))
        }
    }
}
