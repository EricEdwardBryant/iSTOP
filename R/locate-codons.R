# ---- Locate codons ----
#' Locate codons in transcripts
#'
#' Locate genome coordinates of a desired set of codons given a data.frame of
#' CDS coordinates (see [CDS]), and its corresponding
#'  [BSgenome][BSgenome::BSgenome] sequence database.
#'
#' @param cds A data.frame of CDS coordinates. See [CDS][CDS#Value] for details
#' on required columns.
#' @param genome A [BSgenome][BSgenome::BSgenome] sequence database,
#' or a [Biostrings][readDNAStringSet]. CDS coordinates in `cds` should
#' correspond to this genome assembly.
#' @param codons A character vecor of codons to consider. Defaults to
#' `c('CAA', 'CAG', 'CGA', 'TGG', 'TGG')` which are all of the codons
#' with iSTOP targetable bases.
#' @param positions An integer vector of positions in `codons` to use for
#' returned coordinates. Should be the same length as `codons`. Defaults to
#' `c(1L, 1L, 1L, 2L, 3L)` which are the positions in `codons` that can be
#' targeted with iSTOP.
#' @param switch_strand A logical vector indicating whether the corresponding
#' `codon` is targeted on the opposite strand. Determines the resulting value of
#' `sg_strand`. Should be the same length as `codons`. Defaults to `c(F, F, F, T, T)`
#' @param cores Number of cores to use for parallel processing with [pblapply][pbapply::pblapply]
#'
#' @details Each transcript is processed independently based on the `tx`
#' column of the `cds` data.frame.
#'
#' **CDS validation** - Each CDS is validated by checking that the coordinates
#' result in a DNA sequence that begins with a start codon, ends with a stop codon,
#' has a length that is a multiple of 3 and has no internal in-frame stop codons.
#'
#' **No match?** - If a CDS passes validation, but does not have any of the
#' considered codons, the transcript will still be included in the resulting
#' data.frame, but coordinates will be missing (i.e. `NA`).
#'
#' @return A data.frame with the following columns where each row represents
#' a single targetable coordinate (codons with multiple targetable coordinates
#' will have a separate row for each):
#'
#'   - __COLUMN-NAME__ _`DATA-TYPE`_ DESCRIPTION
#'   - __tx__           _`chr`_ Transcript symbol
#'   - __gene__         _`chr`_ Gene symbol
#'   - __exon__         _`int`_ Exon rank in gene
#'   - __pep_length__   _`int`_ Lenth of peptide
#'   - __cds_length__   _`int`_ Length of CDS DNA
#'   - __chr__          _`chr`_ Chromosome
#'   - __strand__       _`chr`_ Strand (+/-)
#'   - __sg_strand__    _`chr`_ Guide strand (+/-)
#'   - __aa_target__    _`chr`_ One letter code of targeted amino acid
#'   - __codon__        _`chr`_ Three letter codon
#'   - __aa_coord__     _`int`_ Coordinate of targeted amino acid (start == 1)
#'   - __cds_coord__    _`int`_ Coordinate of targeted base in CDS (start == 1)
#'   - __genome_coord__ _`int`_ Coordinate of targeted base in genome
#'   - __NMD_pred__     _`lgl`_ Is nonsense-mediated-decay predicted (i.e. target base is >56 bases upstream of last exon junction)
#'   - __rel_position__ _`dbl`_ Relative position in CDS of the targeted base
#'
#' @importFrom purrr map map2 pmap is_character is_integer is_logical
#' @importFrom tibble tibble lst
#' @importFrom BSgenome getSeq
#' @importFrom Biostrings DNAStringSet translate
#' @importFrom pbapply pblapply
#' @export
#' @md

locate_codons <- function(cds,
                          genome,
                          codons = c('CAA', 'CAG', 'CGA', 'TGG', 'TGG'),
                          positions = c(1L, 1L, 1L, 2L, 3L),
                          switch_strand = c(F, F, F, T, T),
                          cores = getOption('mc.cores', 1L)) {

  message('Locating codon coordinates...')

  assert_that(
    cds %has_name% 'tx',  cds %has_name% 'gene',   cds %has_name% 'exon',
    cds %has_name% 'chr', cds %has_name% 'strand', cds %has_name% 'start',
    cds %has_name% 'end',
    length(codons) == length(positions),
    length(codons) == length(switch_strand),
    is_character(codons),
    is_integer(positions),
    is_logical(switch_strand),
    is_integer(cds$start),
    is_integer(cds$end),
    is.count(cores),
    all(cds$strand %in% c('+', '-')),
    class(genome) %in% c('BSgenome', 'DNAStringSet'),
    all(cds$chr %in% names(genome))
  )

  if (cores <= 1L) cores <- NULL

  # Progress bar nonsense
  pbo <- pbapply::pboptions(type = 'timer', char = '=')
  on.exit(pbapply::pboptions(pbo), add = TRUE)

  result <-
    cds %>%
    split(.$tx) %>%
    pbapply::pblapply(locate_codons_of_one_tx, genome, codons, positions, switch_strand, cl = cores) %>%
    bind_rows

  if (nrow(result) < 1) {
    warning('None of the searched CDS sequences met the criteria of:\n',
         '    1. Begin with ATG\n',
         '    2. End with TAA|TAG|TGA\n',
         '    3. Sequence length that is a multiple of 3\n',
         '    4. No internal in-frame TAA|TAG|TGA\n')
  }
  return(result)
}



locate_codons_of_one_tx <- function(cds, genome, codons, positions, switch_strand) {

  # Explicitely arrange exons by increasing exon number
  cds <- arrange(cds, exon)

  # Define constants
  opposite <- c('+' = '-', '-' = '+')

  # Construct CDS from exons
  cds_dna <-
    BSgenome::getSeq(genome, as(select(cds, chr, strand, start, end), 'GRanges')) %>%
    as.character %>%
    str_c(collapse = '')

  # Split CDS into codon vector
  cds_codon_starts <- seq(1, str_length(cds_dna), by = 3L)
  cds_codon_ends   <- cds_codon_starts + 2L
  cds_codons       <- str_sub(cds_dna, start = cds_codon_starts, end = cds_codon_ends)

  # The CDS must be properly formed, if fail, don't count as transcript
  cds_pass <-
    head(cds_codons, n = 1L) %in% c("ATG") &                    # Must begin with start codon
    tail(cds_codons, n = 1L) %in% c("TAA", "TAG", "TGA") &      # Must end with stop codon
    nchar(cds_dna) %% 3 == 0L &                                 # Sequence must be multiple of 3
    length(which(cds_codons %in% c("TAA", "TAG", "TGA"))) == 1L # Sequence must have only one stop codon

  if (!cds_pass) {
    return(NULL)
  }

  # Indices of features at each position in CDS
  index_genome  <- with(cds, get_genomic_index(strand, start, end))
  index_chr     <- with(cds, rep(chr,     times = abs(end - start) + 1))
  index_strand  <- with(cds, rep(strand,  times = abs(end - start) + 1))
  index_exon    <- with(cds, rep(exon,    times = abs(end - start) + 1))
  NMD_boundary  <- which(index_exon == max(index_exon))[1] - 56

  # Find codon targets
  cds_coord <-
    tibble::lst(codons, positions, switch_strand) %>%
    pmap(function(codons, positions, switch_strand) {
      cds_position_of_first_base_in_codon <-
        cds_codon_starts[which(cds_codons %in% codons)]

      cds_coord <- cds_position_of_first_base_in_codon + positions - 1L
      tibble(cds_coord) %>%
        mutate(
          codon = codons,
          codon_position = positions,
          switch_strand = switch_strand
        )
    }) %>%
    bind_rows()

  # Construct a basic results data frame
  result <-
    tibble(
      tx           = unique(cds$tx),
      gene         = unique(cds$gene),
      cds_length   = nchar(cds_dna),
      pep_length   = as.integer(cds_length / 3)
    )

  # Exit if no codons were found
  if (nrow(cds_coord) < 1L) {
    return(result) # Will be counted as a valid transcript with no matches
  }

  # Using genome coordinates of desired base in codon matches to extract nearby sequence
  cds_coord %>%
    mutate(
      tx           = result$tx,
      gene         = result$gene,
      exon         = index_exon[cds_coord],
      pep_length   = result$pep_length,
      cds_length   = result$cds_length,
      chr          = index_chr[cds_coord],    # chr is exon dependent
      strand       = index_strand[cds_coord], # strand is exon dependent
      sg_strand    = ifelse(switch_strand, opposite[strand], strand),
      aa_target    = codon %>% Biostrings::DNAStringSet() %>% Biostrings::translate() %>% as.character,
      genome_coord = index_genome[cds_coord],
      aa_coord     = as.integer(ceiling(cds_coord / 3)),
      NMD_pred     = cds_coord < NMD_boundary,
      rel_position = cds_coord / cds_length
    ) %>%
    select(tx:aa_target, codon, aa_coord, cds_coord, genome_coord, NMD_pred, rel_position) %>%
    arrange(cds_coord)
}


# Given vectors of strand, start, and end, generate a vector of integers between each
# start and end point with respect to strand orientation
get_genomic_index <- function(strand, start, end) {
  tibble::lst(strand, start, end) %>%
    pmap(function(strand, start, end) switch(strand, '+' = start:end, '-' = end:start)) %>%
    unlist
}
