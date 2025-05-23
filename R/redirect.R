#' redirect
#'
#' Redirect a given dataset type to a different source folder.
#' The redirection is local by default, so it will be reset when the current
#' function call returns. See example for more details.
#'
#' Redirecting only specific subtypes is not supported to avoid tricky cases
#' where the subtype is ignored (search for "getSourceFolder\(.*subtype = NULL\)").
#'
#' @param type Dataset name, e.g. "Tau" to set the source folder that \code{\link{readTau}} will use
#' @param target Either path to the new source folder that should be used instead of the default,
#' or NULL to remove the redirection, or a vector of paths to files which are then symlinked
#' into a temporary folder that is then used as target folder; if the vector is named the names
#' are used as relative paths in the temporary folder, e.g. target = c(`a/b/c.txt` = "~/d/e/f.txt")
#' would create a temporary folder with subfolders a/b and there symlink c.txt to ~/d/e/f.txt.
#' @param linkOthers If target is a list of files, whether to symlink all other files in the original
#' source folder to the temporary folder.
#' @param local If TRUE the redirection is only temporary and will be reset
#' when the function which calls redirect is finished. Set to FALSE for a
#' permanent/global redirection or to an environment for more control.
#' @return Invisibly, the source folder that is now used for the given type
#' @author Pascal Sauer
#' @examples \dontrun{
#' f <- function() {
#'   redirect("Tau", target = "~/TauExperiment")
#'   # the following call will change directory
#'   # into ~/TauExperiment instead of <getConfig("sourcefolder")>/Tau
#'   readSource("Tau")
#' }
#' f()
#' # Tau is only redirected in the local environment of f,
#' # so it will use the usual source folder here
#' readSource("Tau")
#' }
redirect <- function(type, target, linkOthers = TRUE, local = TRUE) {
  if (isTRUE(local)) {
    local <- parent.frame()
  }

  if (!is.null(target)) {
    preservedNames <- names(target)
    target <- normalizePath(target, mustWork = TRUE)
    names(target) <- preservedNames
    if (length(target) >= 2 || !dir.exists(target)) {
      target <- redirectFiles(type, target, linkOthers, local)
    }

    # paths inside the source folder use the fileHashCache system, see getHashCacheName,
    # to prevent that we need to make sure that the target is not inside the source folder
    stopifnot(!startsWith(normalizePath(target), normalizePath(getConfig("sourcefolder"))))
  }

  redirections <- getConfig("redirections")
  redirections[[type]] <- target
  setConfig(redirections = redirections, .local = local)
  return(invisible(target))
}

redirectFiles <- function(type, target, linkOthers, local) {
  link <- getLinkFunction()
  # redirect to files
  if (isFALSE(local)) {
    tempDir <- tempfile()
    dir.create(tempDir)
  } else {
    tempDir <- withr::local_tempdir(.local_envir = local)
  }
  if (is.null(names(target))) {
    names(target) <- basename(target)
  } else {
    # append basename to target path if it ends with "/"
    i <- endsWith(names(target), "/")
    names(target)[i] <- paste0(names(target)[i], basename(target[i]))

    for (p in file.path(tempDir, names(target))) {
      if (!dir.exists(dirname(p))) {
        dir.create(dirname(p), recursive = TRUE)
      }
    }
  }
  link(target, file.path(tempDir, names(target)))

  if (linkOthers) {
    # symlink all other (not in target) files in original source folder
    dontlink <- lapply(names(target), parentFolders) # find all parent folders
    dontlink <- unique(do.call(c, dontlink)) # flatten and remove duplicates

    sourceFolder <- getSourceFolder(type, subtype = NULL)
    withr::with_dir(sourceFolder, {
      dirs <- Filter(dir.exists, dontlink)
      linkThese <- lapply(c(".", dirs), dir, all.files = TRUE, no.. = TRUE, full.names = TRUE)
    })
    linkThese <- do.call(c, linkThese)
    linkThese <- sub("^\\./", "", linkThese)
    linkThese <- setdiff(linkThese, dontlink)
    if (length(linkThese) > 0) {
      link(file.path(sourceFolder, linkThese),
           file.path(tempDir, linkThese))
    }
  }

  return(tempDir)
}

parentFolders <- function(path, collected = NULL) {
  if (path == ".") {
    return(collected)
  }
  return(parentFolders(dirname(path), c(path, collected)))
}
