##################
## masala-merge ##
##################

## define fuzzy-name match function
masala_merge <- function(df_master, df_using, columns, s1, outfile, fuzziness = 1, sortwords = "", tmp, MASALA_PATH) {

    ## ensure that df_master and df_using are data.frame
    df_master <- as.data.frame(df_master)
    df_using <- as.data.frame(df_using)

    ## define max levenshtein distance
    max_dist <- 0.40 + 1.25 * 2.1 * fuzziness

    time <- as.numeric(gsub(":", "", format(Sys.time(), "%H:%M:%S")))
    nonce <- floor(time * runif(1) + 1)

    df_master <- df_master %>% select(all_of(c(columns, s1))) %>% arrange(!!!syms(c(columns, s1)))

    ## merge two datasets on columns
    lev_groups <- merge(df_master, select(df_using, columns, s1), by = columns, all = TRUE)

    ## generate id groups
    lev_groups$g <- as.numeric(interaction(lev_groups[columns]))
    lev_groups <- lev_groups %>% filter(!is.na(g))

    num_groups <- max(lev_groups$g)

    ## save group list
    lev_groups <- lev_groups %>% select(g, columns) %>% distinct()

    ## drop if missing string and store observation count
    df_master <- df_master %>% filter(!is.na(!!sym(s1)))
    g1_count <- nrow(df_master)

    ## bring in group identifiers
    src1 <- merge(df_master, select(lev_groups, columns, g), by = columns) %>% distinct() %>% select(g, s1, everything())

    ## export string group 1
    write.table(select(src1, g, s1), file = file.path(tmp, paste0("src1_", nonce, ".txt")), sep = ",", row.names = FALSE, col.names = FALSE)
    
    ## prepare group 2
    df_using <- df_using %>% select(columns, s1)
    
    ## confirm no duplicates on this side
    df_using <- df_using %>% group_by(!!!syms(c(columns, s1))) %>% mutate(dup = n() - 1) %>% ungroup()
    if (sum(df_using$dup > 0) > 0) {
        stop(paste(varlist, s1, "not unique on using side"), call. = FALSE)
    }
    df_using <- df_using %>% select(-dup)

    ## drop if missing string and store observation count
    df_using <- df_using %>% filter(!is.na(!!sym(s1)))
    g2_count <- nrow(df_using)

    ## merge in group identifiers
    src2 <- merge(df_using, select(lev_groups, columns, g), by = columns) %>% distinct() %>% select(g, s1, everything())

    ## export string group 2
    write.table(select(src2, g, s1), file = file.path(tmp, paste0("src2_", nonce, ".txt")), sep = ",", row.names = FALSE, col.names = FALSE)

    ## call python levenshtein program
    print(paste("Matching", g1_count, "strings to", g2_count, "strings in", num_groups, "groups."))
    print("Calling lev.py:")

    print(paste("shell python -u", file.path(MASALA_PATH, "lev.py"), "-d", max_dist, "-1", file.path(tmp, paste0("src1_", nonce, ".txt")), "-2", file.path(tmp, paste0("src1_", nonce, ".txt")), "-o", file.path(tmp, paste0("out_", nonce, ".txt")), sortwords))
    system(paste("python", file.path(MASALA_PATH, "lev.py"), "-d", max_dist, "-1", file.path(tmp, paste0("src1_", nonce, ".txt")), "-2", file.path(tmp, paste0("src2_", nonce, ".txt")), "-o", file.path(tmp, paste0("out_", nonce, ".txt")), sortwords))

    print("lev.py finished.")

    out <- read.table(file.path(tmp, paste0("out_", nonce, ".txt")), sep = ",", header = FALSE, strip.white = TRUE)

    out <- out %>% rename(g = V1, !!paste0(s1, "_master") := V2, !!paste0(s1, "_using") := V3, lev_dist = V4)

    ## merge group identifiers back in
    out <- out %>% mutate(g = as.numeric(g)) %>% merge(select(lev_groups, g, columns), by = "g")

    ## count specificity of each match
    out <- out %>% group_by(g, !!sym(paste0(s1, "_master"))) %>% mutate(master_matches = sum(!is.na(g))) %>% ungroup() %>%
        group_by(g, !!sym(paste0(s1, "_using"))) %>% mutate(using_matches = sum(!is.na(g))) %>% ungroup()

    ## count distance to second best match
  
    ## calculate best match for each var
    for (v in c("master", "using")) {
        out <- out %>% group_by(g, !!sym(paste0(s1, "_", v))) %>% mutate(!!paste0(v, "_dist_rank") := rank(lev_dist, ties.method = "first")) %>% ungroup() %>%
            mutate(tmp = ifelse(!!sym(paste0(v, "_dist_rank")) == 1, lev_dist, NA)) %>% 
            group_by(g, !!sym(paste0(s1, "_", v))) %>% mutate(!!sym(paste0(v, "_dist_best")) := max(tmp, na.rm = TRUE)) %>%
            mutate(!!sym(paste0(v, "_dist_best")) := ifelse(is.infinite(!!sym(paste0(v, "_dist_best"))), NA, !!sym(paste0(v, "_dist_best")))) %>% ungroup() %>% select(-tmp) %>%
            mutate(tmp = ifelse(!!sym(paste0(v, "_dist_rank")) == 2, lev_dist, NA)) %>%
            group_by(g, !!sym(paste0(s1, "_", v))) %>% mutate(!!sym(paste0(v, "_dist_second")) := max(tmp, na.rm = TRUE)) %>%
            mutate(!!sym(paste0(v, "_dist_second")) := ifelse(is.infinite(!!sym(paste0(v, "_dist_second"))), NA, !!sym(paste0(v, "_dist_second")))) %>% ungroup() %>% select(-tmp, -!!paste0(v, "_dist_rank"))
    }

    out <- out %>% select(-g)
    
    ## apply optimal matching rule (based on 1991-2001 pop census confirmed village matches in calibrate_fuzzy.do)
    ## initialize
    out$keep_master <- 1
    out$keep_using <- 1

    ## get mean length of matched string
    out$length = floor(0.5 * (nchar(out[[paste0(s1, "_master")]]) + nchar(out[[paste0(s1, "_using")]])))

    ## 1. drop matches with too high a levenshtein distance (threshold is a function of length)
    out <- out %>% mutate(keep_master = ifelse(lev_dist > (0.9 * fuzziness) & length <= 4, 0, keep_master)) %>%
        mutate(keep_master = ifelse(lev_dist > (1.0 * fuzziness) & length <= 5, 0, keep_master)) %>%
        mutate(keep_master = ifelse(lev_dist > (1.3 * fuzziness) & length <= 8, 0, keep_master)) %>%
        mutate(keep_master = ifelse(lev_dist > (1.4 * fuzziness) & between(length, 9, 14), 0, keep_master)) %>%
        mutate(keep_master = ifelse(lev_dist > (1.8 * fuzziness) & between(length, 15, 17), 0, keep_master)) %>%
        mutate(keep_master = ifelse(lev_dist > (2.1 * fuzziness), 0, keep_master))

    ## copy these thresholds to keep_using
    out <- out %>% mutate(keep_using = ifelse(keep_master == 0, 0, keep_using))

    ## 2. never use a match that is not the best match
    out <- out %>% mutate(keep_master = ifelse((lev_dist > master_dist_best) & !is.na(lev_dist), 0, keep_master)) %>%
        mutate(keep_using = ifelse((lev_dist > using_dist_best) & !is.na(lev_dist), 0, keep_using))
        
    ## 3. apply best empirical safety margin rule
    out <- out %>% mutate(keep_master = ifelse((master_dist_second - master_dist_best) < (0.4 + 0.25 * lev_dist) & !is.na(master_dist_second), 0, keep_master)) %>%
        mutate(keep_using = ifelse((using_dist_second - using_dist_best) < (0.4 + 0.25 * lev_dist) & !is.na(using_dist_second), 0, keep_using))

    ## save over output file
    out <- out %>% select(columns, !!paste0(s1, "_master"), !!paste0(s1, "_using"), lev_dist, keep_master, keep_using, starts_with("master_"), starts_with("using_"), everything())
    saveRDS(as.data.frame(out), outfile)
}
