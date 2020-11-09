/* Run masala_merge on example data.

master dataset: 1 day of district-level covid case data from www.covid19india.org
using dataset: government-standardized state and district names from https://lgdirectory.gov.in/ 

In this example, we want to merge the district names being used by 
the open source covid database to make the data interoperale with 
other India government datasets.
 */

/* set the path for the masala_merge repository */
global masalapath $ddl/masala-merge

/* masala_merge uses a temprorary directory to write intermediate
   files as well. set the $tmp global to whatever path you want. */
// global tmp

/* open the data */
use $masalapath/tests/data/covid_case_data, clear

/* rename state and district variables to match the using dataset */
ren state lgd_state_name
ren district lgd_district_name

/* run masala_merge */
masala_merge lgd_state_name using $masalapath/tests/data/standard_district_names, s1(lgd_district_name) minbigram(0.6) minscore(0.7) outfile($masalapath/tests/data/matched_districts)


