iSTOP - an R package for designing induced stop mutants
=======================================================

Quick usage examples
====================

``` r
library(tidyverse)
library(iSTOP)

# Download CDS coordinates for a genome assembly
# Be polite to UCSC - avoid repeated downloads!
CDS_Scerevisiae_UCSC_sacCer3() %>% write_csv('~/Desktop/CDS-Yeast.csv')

# Read your previously saved CDS coordinates
Yeast_CDS    <- read_csv('~/Desktop/CDS-Yeast.csv')
Yeast_Genome <- BSgenome.Scerevisiae.UCSC.sacCer3::Scerevisiae

# Detect iSTOP targets for a single gene
SUS1 <- 
  Yeast_CDS %>%
  filter(gene == 'SUS1') %>%
  locate_codons(Yeast_Genome) %>%
  locate_iSTOP(Yeast_Genome)

# Detect iSTOP targets for genes that contain "RAD"
RAD <- 
  Yeast_CDS %>%
  filter(grepl('RAD', gene)) %>%
  locate_codons(Yeast_Genome) %>%
  locate_iSTOP(Yeast_Genome)

# Detect iSTOP targets for a set of transcript IDs
SET1 <-
  Yeast_CDS %>%
  filter(tx %in% c('YGR248W', 'YER006C-A')) %>%
  locate_codons(Yeast_Genome) %>%
  locate_iSTOP(Yeast_Genome)

# Visualize
# Coming soon!
```

Installation
============

First, instal [R](https://cran.r-project.org). Installing [RStudio](https://www.rstudio.com/products/rstudio/download/) is also recommended. Once installed, open RStudio and run the following commands in the console to install all necessary R packages.

``` r
# Source the Biocoductor installation tool - installs and loads the BiocInstaller 
# package which provides the biocLite function.
source("https://bioconductor.org/biocLite.R")

# Install the following required packages (their dependencies will be included)
biocLite(c(
  # Packages from CRAN (cran.r-project.org)
  'tidyverse', 
  'assertthat',
  'pbapply',
  'devtools',
  # Packages from Bioconductor (bioconductor.org)
  'BSgenome',
  'Biostrings',
  'GenomicRanges',
  'IRanges'))

# If all went well, install the iSTOP package hosted on GitHub
biocLite('ericedwardbryant/iSTOP')
```

Detailed usage example
======================

Load the following packages to make their contents available.

``` r
# Load packages to be used in this analysis
library(tidyverse)
library(iSTOP)
```

To locate iSTOP targets you will also need the following:

1.  CDS coordinates
2.  Genome sequence

CDS coordinates
---------------

This is an example table of CDS coordinates for *S. cerevisiae* *RAD14*.

| tx      | gene  | exon | chr     | strand | start  | end    |
|:--------|:------|:-----|:--------|:-------|:-------|:-------|
| YMR201C | RAD14 | 1    | chrXIII | -      | 667018 | 667044 |
| YMR201C | RAD14 | 2    | chrXIII | -      | 665845 | 666933 |

This gene has a single transcript "YMR201C" which is encoded on the "-" strand and has two exons (1 row for each exon). Note that, since this gene is encoded on the "-" strand, the first base in the CDS is located on chrXIII at position 667044, and the last base in the CDS is at position 665845. It is critial that exons are numbered with respect to CDS orientation. Chromosomes should be named to match the sequence names in your genome. Strand must be either "+", or "-".

The `CDS` function will generate a CDS table from annotation tables provided by the UCSC genome browser. Type `?CDS` in the R console to view the documentation of this function. Note that the documentation for `CDS` lists several pre-defined functions to access complete CDS coordinates for a given species and genome assembly. The example below will download and construct a CDS coordinates table for the Human genome hg38 assembly. Note that only exons that contain coding sequence are retained, hence some transcripts not having coordinates for e.g. exon \#1.

``` r
CDS_Hsapiens <- CDS_Hsapiens_UCSC_hg38()
```

Other pre-defined CDS functions include:

| Type  | Species           | CDS function                           |
|:------|:------------------|:---------------------------------------|
| Worm  | *C. elegans*      | `CDS_Celegans_UCSC_ce11()`             |
| Fly   | *D. melanogaster* | `CDS_Dmelanogaster_UCSC_dm6()`         |
| Fish  | *D. rerio*        | `CDS_Dreriio_UCSC_danRer10()`          |
| Human | *H. sapiens*      | `CDS_Hsapiens_UCSC_hg38()`             |
| Mouse | *M. musculus*     | `CDS_Mmusculus_UCSC_mm10()`            |
| Rat   | *R. norvegicus*   | `CDS_Rnorvegicus_UCSC_rn6()`           |
| Yeast | *S. cerevisiae*   | `CDS_Scerevisiae_UCSC_sacCer3()`       |
| Plant | *A. thaliana*     | `CDS_Athaliana_BioMart_plantsmart28()` |

Genome sequence
---------------

### Using a BSgenome package

Pre-built genome sequence packages are provided by Bioconductor as "BSgenome" packages. To get a list of all available BSgenome packages you can run `BSgenome::available.genomes()`. For this example we will install the BSgenome package that corresponds to the hg38 assemply (as this matches the CDS coordinates we downloaded earlier).

``` r
# Note that the package only needs to be installed once. No need to run this again.
BiocInstaller::biocLite('BSgenome.Hsapiens.UCSC.hg38')
```

Once installed we can access the genome object like so:

``` r
Genome_Hsapiens <- BSgenome.Hsapiens.UCSC.hg38::Hsapiens
```

### Or, using fasta sequence files

Alternatively, you can construct a genome manually from a set of fasta files. Just make sure that the sequence names match those in the `chr` column of your CDS coordinates table and that the CDS coordinates are compatible with these sequences. This is not the recommended approach as sequence lookups are slower, but if this is what you have, or you

``` r
# Build custom genome of Human chromosomes X and Y
Genome_Hsapiens_XY <- Biostrings::readDNAStringSet(
  c('http://hgdownload.soe.ucsc.edu/goldenPath/hg38/chromosomes/chrX.fa.gz',
    'http://hgdownload.soe.ucsc.edu/goldenPath/hg38/chromosomes/chrY.fa.gz'))
```

Seach for iSTOP
===============

``` r
# I will be limiting this analysis to chromosomes X and Y
Hooray <-
  CDS_Hsapiens %>%
  filter(chr %in% c('chrX', 'chrY')) %>%
  locate_codons(Genome_Hsapiens) %>%
  locate_iSTOP(Genome_Hsapiens)
```

``` r
# This analysis will be limited to PLCXD1 and uses the FASTA sequences
# Note that using FASTA sequences is MUCH slower than using a BSgenome
Hooray_XY <-
  CDS_Hsapiens %>%
  filter(gene == 'PLCXD1') %>%
  locate_codons(Genome_Hsapiens_XY) %>%
  locate_iSTOP(Genome_Hsapiens_XY)
```

Issues? Requests?
=================

If you have a feature request or have identified an issue, please submit them [here](https://github.com/EricEdwardBryant/iSTOP/issues).
