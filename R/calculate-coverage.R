
#' Function to calculate coverage over set of genomic intervals given BAM file and loci file
#'
#' Takes a BAM file and a genomic interval file as input and returns coverage for each
#' interval. Uses the \code{scanBam} function if QC option is set to TRUE
#' and applies low quality, duplicate reads as well as secondary alignment
#' filters.
#'
#'
#' @param bam.file Filename of a BAM file.
#' @param interval.file File specifying the intervals. Interval is expected in
#' first column in format CHR:START-END. 
#' @param qc_file Logical flag specifying if bam file needs to be QC'ed and filtered for low quality, duplicate reads as well as secondary alignment
#' filters.
#' @param output.file Optionally, write minimal coverage file. Can be read with
#' the \code{\link{readCoverageFile}} function.
#' @param index.file The bai index. Used only if \param qc_file is set to 'TRUE'
#' @param keep.duplicates Logical flag specifying to keep or remove duplicated reads.  Used only if \param qc_file is set to 'TRUE'
#' @param ... Additional parameters passed to \code{ScanBamParam}.
#' @return Returns raw readcount and TPM overlapping genomic intervals 
#' @author Aditi Qamra
#' @seealso \code{\link{preprocessIntervals}
#' @examples
#'
#' bam.file <- system.file("extdata", "ex1.bam", package = "APcalc")
#' interval.file <- system.file("extdata", "ex1_intervals.txt",package = "APcalc")
#'
#' # Calculate raw coverage from BAM file
#' coverage <- calculateBamCoverageByInterval(bam.file = bam.file,
#'     interval.file = interval.file)
#'
#' @export calculateBamCoverageByInterval
#' @importFrom Rsamtools headerTabix ScanBamParam scanBamFlag
#'             scanBam scanFa scanFaIndex TabixFile
#'             

calculateBamCoverageByInterval <- function(bam.file, 
                                           interval.file,
                                           output.file = NULL, 
                                           qc_file=TRUE,
                                           index.file = NULL, 
                                           keep.duplicates = FALSE,
                                           ...) {
  
  intervalGr <- readCoverageFile(interval.file)
  
  param <- ScanBamParam(what = c("pos", "qwidth", "flag"),
                        which = intervalGr,
                        flag = scanBamFlag(isUnmappedQuery = FALSE,
                                           isNotPassingQualityControls = FALSE,
                                           isSecondaryAlignment = FALSE,
                                           isDuplicate = NA
                        ),
                        ...
  )
  
  xAll <- scanBam(bam.file, index = index.file, param = param)
  xDupFiltered <- .filterDuplicates(xAll)
  
  x <- xDupFiltered
  if (keep.duplicates) x <- xAll
  
  intervalGr$coverage <- vapply(seq_along(x), function(i)
    sum(coverage(IRanges(x[[i]][["pos"]], width = x[[i]][["qwidth"]]),
                 shift = -start(intervalGr)[i], width = width(intervalGr)[i])), integer(1))
  
  intervalGr$average.coverage <- intervalGr$coverage / width(intervalGr)
  
  intervalGr$counts <- as.numeric(vapply(x, function(y) length(y$pos), integer(1)))
  intervalGr$duplication.rate <- 1 -
    vapply(xDupFiltered, function(y) length(y$pos), integer(1)) /
    vapply(xAll, function(y) length(y$pos), integer(1))
  
  if (!is.null(output.file)) {
    .writeCoverage(intervalGr, output.file)
  }
  invisible(intervalGr)
}

.writeCoverage <- function(intervalGr, output.file) {
  tmp <- data.frame(
    Target = as.character(intervalGr),
    total_coverage = intervalGr$coverage,
    counts = intervalGr$counts,
    on_target = intervalGr$on.target,
    duplication_rate = intervalGr$duplication.rate
  )
  fwrite(tmp, file = output.file, row.names = FALSE, quote = FALSE,
         sep = " ", logical01 = TRUE, na = "NA")
}

.filterDuplicates <- function(x) {
  lapply(x, function(y) {
    idx <- y$flag < 1024
    lapply(y, function(z) z[idx])
  })
}
