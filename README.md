# Masala Merge

A fuzzy string matching algorithm designed for Indian place and person names. 

`masala-merge` tries to make intelligent choices for you, to get the best possible match in the first pass. Some features:

- `masala-merge` tries multiple fuzzy match methods:

  - Levenshtein, an edit distance with customized costs for common substitutions in Indian text, e.g. `KS->X`

  - Stata's `reclink`, which matches based on shared content. `reclink` is good at matching "Tata Steel Incorporated" with "Tata Steel Inc".

- ambiguous matches are excluded by default. For example, if you are looking for a match for the word "Soni", and the target dataset includes both "Suni" and "Sonni", by default `masala-merge` is conservative and will not make this match. (See below to turn this off.)

- `masala-merge` outputs a CSV of unmatched observations, which can be used to create manual matches for future merges.


## Requirements

Python 3.2 (may work with other versions)

`$tmp` and `$MASALA_PATH` must be defined. `$tmp` is a folder for
storage of temporary files. `$MASALA_PATH` is the path containing
`lev.py`, included in this package.

## Sample usage

Stata: 
```
/* Find matches for community_name, within states */
masala_merge state_name using $tmp/target_key, s1(community_name) method(levonly) keepambiguous fuzzines(0.5)
```

R:
```
masala_merge(df_master, df_using, c("pc01_state_id", "group"), "surname", outfile = /path/to/output/, tmp = /path/to/tmp/, MASALA_PATH = /path/to/masala/)
```

## Parameters

### Required Arguments

- `varlist`: Variables defining the within-group match pools. For example, "state district" if you are looking to match villages only within districts.

- `s1`: The match variable (must be the same name in both master and using datasets). This is the string variable that will be fuzzy matched. If you want to fuzzy match multiple levels of strings, you need to use `masala-merge` in multiple rounds.

### Optional Arguments

- `idmaster`: Unique string ID for the master dataset. If not specified, created internally as varlist-s1. Data must be unique on varlist-s1 if not specified. We recommend using both `idmaster` and `idusing` as it makes the merge result and intermediate files easier to interpret.

- `idusing`: Unique string ID for the using dataset. If not specified, created internally as varlist-s1. Data must be unique on varlist-s1 if not specified.

- `listvars`: Additional variables you want retained to help identify manual matches. These will be included in the output CSV of unmatched observations.

- `manual_file`: Full filepath for the input CSV that contains human-created manual matches. If not specified, no manual matches will be incorporated.

- `csvsort`: Variable on which to sort the CSV of unmatched observations. Defaults to `s1`.

- `method`: Which matching methods to use. Options are:
  - `levonly`: Use only Levenshtein distance matching (default)
  - `rlonly`: Use only RecLink matching
  - `both`: Use both methods

- `nopreserve`: If specified, will not preserve the original data. Useful for debugging.

- `fuzziness`: How much uncertainty to allow in the matches. The default is 1.0, lower numbers will give more certainty but fewer matches.

- `minscore`: RecLink argument for match uncertainty threshold. Overrides fuzziness if specified, otherwise generated from fuzziness value.

- `minbigram`: RecLink argument for weighting of string length in uncertainty threshold. Overrides fuzziness if specified, otherwise generated from fuzziness value.

- `outfile`: Filepath where intermediate matching results should be saved.

- `keepusing`: Variables from the using dataset to keep in the final merged result.

- `sortwords`: If specified, sorts words within strings before comparing them. This will cause "Tata Steel" to have a good Levenshtein match with "Steel Tata".

- `keepambiguous`: If specified, keeps ambiguous matches (where multiple good matches exist) instead of dropping them. Will arbitrarily select one match when multiple equally good matches exist.

- `nonameclean`: If specified, skips the name cleaning step before matching. Name cleaning strips special characters, converts to lowercase, and removes diacritics, etc..

## Output

`masala-merge` returns a merged dataset with the following key variables:

- `match_source`: Indicates how each observation was matched (e.g. reclink, levenshtein, both, manual, unmatched master, unmatched using).

- `masala_dist`: Overall measure of match distance for found matches (lower is better)

- `_merge`: Standard Stata merge result indicator (1/2/3)

The program also outputs unmatched observations to a CSV file that can be used to create manual matches for future merges.

## Generating Manual Matches

`masala-merge` outputs a CSV file with remaining unmatched observations. This file is structured so that you can easily review and identify new matching pairs, and also incorporate those manual matches into a new run of `masala-merge`.

Here is a sample output file. The sorting helps us see that "agarwal" and "agrawal" should probably have been matched. (This is a contrived example, because masala-merge would have found that match!)

```
output_2345.csv
_state_name   , _name_master, _name_using, idu_using  , idm_master, idu_match
AP            , acchu       ,            ,            , AP-acchu  ,
AP            , agrawal     ,            ,            , AP-agrawal,
AP            ,             , agarwal    , AP-agarwal ,           ,
```

To incorporate this manual match, we add the idusing value to the `idu_match` column for the manual match.

```
output_2345.csv
_state_name   , _name_master, _name_using, idu_using  , idm_master, idu_match
AP            , acchu       ,            ,            , AP-acchu  ,
AP            , agrawal     ,            ,            , AP-agrawal, AP-agarwal
AP            ,             , agarwal    , AP-agarwal ,           ,
```

To incorporate the manual matches, we first run `process_manual_matches`:

```
process_manual_matches, outfile(manual_matches.csv) infile(output_2345.csv) S1(name) idmaster(idm_master) idusing(idu_using) [charsep(string)]
```

This creates a `manual_matches.csv` file. We then go back and re-run the earlier `masala-merge`, adding the parameter `manual_file(manual_matches.csv)` parameter. `masala-merge` will incorporate the new manual matches.


## Handling ambiguous matches

The default `masala-merge` behavior is to reject matches where there are two very similar targets. The idea is that the target/using dataset is canonical, so if we can't match one target with certainty, we prefer to match nothing. For example, if your target is a known list of districts, if one district match is only 1% better than another, we generally don't want the match, preferring unmatched to errors.

If the target dataset has multiple rows indicating the same target (e.g. it might have Agarwal and Agrawal, and we're happy with a match to either one), add the option `keepambiguous` to the command. `masala-merge` will then keep the best match. If there are two equally good matches, it will arbitrarily select one.

If there are any ambiguous matches, you will see a message like the following:

```
+--------------------------------------------------------------------------------------
| WARNING: Some master entries had multiple good fits on the using side!
+--------------------------------------------------------------------------------------
 You can review these rows here (1235): /dartfs-hpc/scratch/pnovosad/ambiguous_38906.dta
 Masala_merge only kept the best match in each case (and picked randomly if two were equally good).
```

The output file will have every candidate match for the ambiguous rows and should be manually inspected. The ambiguous match file has the following structure:

```
_community_name_master    # Fuzzy name in the master dataset (in this case s1 was community_name)
_community_name_using     # Fuzzy name in the using dataset
lev_dist                  # Masala distance (levenshtein or reclink) between the master and using names
g                         # Group identifier for the match (e.g. state)
master_dist_best          # Distance to best match in master dataset
master_dist_second        # Distance to second best match in master dataset
keep_master               # Flag indicating the row that was kept
length                    # Length of the shorter of the master or using string
any_ambiguous_match       # Flag indicating if this match was ambiguous (always true in this dataset)
ambiguous_match           # Flag indicating if this specific match was considered candidate

```

If you want to override the ambiguous match behavior, one way is to run `masala-merge` with defaults (i.e. no `keepambiguous` option), and then make the matches you want in the manual match file (see above).

## Customizing `masala_merge`

`masala_merge` runs a Levenshtein "edit distance" algorithm that counts
the number of insertions, deletions and character changes that are
required to get from one string to another. We have modified the
Levenshtein algorithm to use smaller penalties for very common
alternate spellings in Hindi. For instance "laxmi" and "lakshmi" have
a Levenshtein distance of 3, but a Masala-Levenshtein distance of only
0.4.

The low cost character changes are described in a list in `lev.py`. If
you would like to modify this for other languages with other common
spelling inconsistencies, then modify these lists with custom
costs that suit your context.

## `fix_spelling`

`fix_spelling` is a shortcut to magically correct spelling errors in a list of
words, given a master list of correct words. It is a wrapper for the simplest use case of `masala-merge`.  For example, suppose you have a dataset with district names, you have a master list of district names (with state identifiers), and you want to modify your current district names to match the master key. The following command will "fix" your misspelled district names:

```
fix_spelling district_name, src(master_district_key.dta) group(state_id) replace
```

`state_id` is a group variable -- districts in state 1 in the open
file will only be fixed based on districts in state 1 in the key
file. With this format, `district_name` and `state_id` both need to
appear in both files. If the variables have different names in the
different datasets, use `targetfield()` and `targetgroup()` to specify
the field and group variables in the using data.

Additional options:

- `gen(varname)` can be used instead of replace
- `targetfield()` and `targetgroup()` can be used if the group or merge
  variable have different names in the master dataset.
- If `keepall` is specified, your dataset will add rows from the
  target list that didn't match anything in your data

Example:

```
. fix_spelling pc01_district_name, src($keys/pc01_district_key) replace group(pc01_state_name) 

[...]

+--------------------------------------------------------------------------------------
| Spelling fixes and levenshtein distances:
+--------------------------------------------------------------------------------------

      +-------------------------------------------+
      | pc01_distri~e         __000000   __0000~t |
      |-------------------------------------------|
  80. |   karimanagar       karimnagar         .2 |
 155. |  mahabubnagar      mahbubnagar         .2 |
 422. |         buxor            buxar        .45 |
 462. |     jahanabad        jehanabad        .45 |
 480. |     khagari a         khagaria        .01 |
      |-------------------------------------------|
 544. |        purnea           purnia        .45 |
 624. |     ahmedabad        ahmadabad        .45 |
 700. |   banaskantha     banas kantha        .01 |
 757. |         dahod            dohad         .8 |
 888. |    panchmahal     panch mahals       1.01 |
      |-------------------------------------------|
 932. |   sabarkantha     sabar kantha        .01 |
 991. |       vadodra         vadodara         .2 |
1490. |         angul           anugul          1 |
1546. |         boudh            baudh        .45 |
1569. |       deogarh         debagarh        1.2 |
      |-------------------------------------------|
1609. | jagatsinghpur   jagatsinghapur         .2 |
1617. |        jajpur          jajapur         .2 |
1674. |        khurda          khordha        .65 |
1722. |   nabarangpur     nabarangapur         .2 |
1922. |    puducherry      pondicherry       1.35 |
      +-------------------------------------------+
```

## R script

`masala_merge.R` is an R script version of `masala_merge.do`. The function takes the master and using dataframes, the columns on which the masala merge is performed, the matching variable, the file path where intermediate results should be saved, `tmp`, and `MASALA_PATH`. It also accepts optional parameters for fuzziness and sortwords.
