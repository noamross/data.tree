#' Convert a \code{\link{Node}} to a \code{data.frame}
#' 
#' @param node The node to convert
#' @param ... the attributes to be added as columns of the data.frame. There are various
#' options:
#' \itemize{
#'  \item a string corresponding to the name of a node attribute
#'  \item the result of the \code{Node$Get} method
#' }
#' If a specific Node does not contain the attribute, the data.frame will contain NA.
#' @param pruneFun a function pruning the nodes to be converted
#' @param inheritFromAncestors If TRUE, then field-attributes from ancestors are inherited
#'
#' @seealso \code{\link{Node}}, \code{\link{as.data.frame.Node}} 
#' @export
ToDataFrameTree <- function(node, ..., pruneFun = NULL, inheritFromAncestors = FALSE) {
  as.data.frame(node, row.names = NULL, optional = FALSE, ..., pruneFun = pruneFun, inheritFromAncestors = inheritFromAncestors)
}

#' Converts the tree to tabular form, keeping only the leafs.
#' 
#' This method is especially useful when you need to apply a specific function that is only available 
#' for \code{\link{data.frame}}. 
#' 
#' @param node The node to convert
#' @param ... character strings representing the attributes to be returned. Note that these may not be 
#' available on a leaf, in which case the algorithm inherits the values from its ancestors.
#' @param pruneFun a function pruning the tree to be converted
#' @param filterFun a function filtering nodes to be converted
#' 
#' @export
ToDataFrameTable <- function(node, ..., pruneFun = NULL, filterFun = NULL) {
  ifilterFun <- function(x) {
    x$isLeaf && (length(filterFun) == 0 || filterFun(x))  
  }
  df <- as.data.frame(node, row.names = NULL, optional = FALSE, ..., pruneFun = pruneFun, filterFun = ifilterFun, inheritFromAncestors = TRUE)
  df[,-1]
}

ToDataFrameTaxonomy <- function(node, 
                                ..., 
                                pruneFun = NULL, 
                                inheritFromAncestors = FALSE) {
  
  t <- Traverse(node, traversal = "level", pruneFun = pruneFun)
  children <- Get(t, "name")
  parents <- Get(t, function(x) x$parent$name)
  level <- Get(t, "level")
  df <- data.frame(children = children, parents = parents, level = level, stringsAsFactors = FALSE)

  df2 <- ToDataFrameTree(acme, ..., pruneFun = pruneFun, inheritFromAncestors = inheritFromAncestors)[,-1, drop = FALSE]
  
  df <- cbind(df, df2)
  
  df[-1,]
}


#' Convert a \code{\link{Node}} to a \code{data.frame}
#' 
#' @param x The root node to convert to a data.frame
#' @param row.names \code{NULL} or a character vector giving the row names for the data frame. 
#' Missing values are not allowed.
#' @param optional logical. If \code{TRUE}, setting row names and converting column names 
#' (to syntactic names: see make.names) is optional.
#' @param ... the attributes to be added as columns of the data.frame. There are various
#' options:
#' \itemize{
#'  \item a string corresponding to the name of a node attribute
#'  \item the result of the \code{Node$Get} method
#' }
#' If a specific Node does not contain the attribute, \code{NA} is added to the data.frame.
#' @param pruneFun a function which, if TRUE is returned, causes the subtree of a Node to be pruned.
#' @param filterFun a function which filters the Nodes added to the \code{data.frame}. The function must
#' take a \code{Node} as an input, and it must return \code{TRUE} or \code{FALSE}, depending on whether the
#' @param inheritFromAncestors if TRUE, then any attribute specified in \code{...} is fetched from a Node, or from any
#' of its ancestors
#' \code{Node} and its subtree should be displayed.
#' 
#' @export
as.data.frame.Node <- function(x, 
                               row.names = NULL, 
                               optional = FALSE, 
                               ..., 
                               traversal = c("pre-order", "post-order", "in-order", "level", "ancestor"),
                               pruneFun = NULL,
                               filterFun = NULL,
                               inheritFromAncestors = FALSE
) {

  traversal <- traversal[1]
  
  if(!x$isRoot) {
    #clone s.t. x is root (for pretty level names)
    x <- x$Clone()
  }
  
  t <- Traverse(x, traversal = traversal, pruneFun = pruneFun, filterFun = filterFun)
  
  df <- data.frame( levelName = format(Get(t, 'levelName')),
                    row.names = row.names,
                    stringsAsFactors = FALSE)
  
  cols <- list(...)
  
  if(length(cols) == 0) return (df)
  for (i in 1:length(cols)) {
    col <- cols[[i]]
    if (length(names(cols)) > 0 && nchar(names(cols)[i]) > 0) colName <- names(cols)[i]
    else if (is.character(col)) colName <- col
    else stop(paste0("Cannot infer column name for ... arg nr ", i))
    if (length(col) > 1) {
      it <- col
    } else {
      it <- Get(t, col, inheritFromAncestors = inheritFromAncestors)
    }
    df[colName] <- it
    
  }
  
  return (df)
  
}

#' Convert a data.frame to a data.tree
#' 
#' @param x The data.frame
#' @param ... Any other argument
#' @param pathName The name of the column in x containing the path of the row
#' @param pathDelimiter The delimiter used
#' @param colLevels Nested vector of column names, determining on what node levels the attributes are written to.
#' @param na.rm If \code{TRUE}, then NA's are treated as NULL and values will not be set on nodes
#' 
#' @details x should be of class x
#' 
#' @export
as.Node.data.frame <- function(x, 
                               ..., 
                               pathName = 'pathString', 
                               pathDelimiter = '/', 
                               colLevels = NULL,
                               na.rm = FALSE) {
  root <- NULL
  mycols <- names(x)[ !(names(x) %in% c(NODE_RESERVED_NAMES_CONST, pathName)) ]
  for (i in 1:nrow(x)) {
    myrow <- x[ i, ]
    mypath <- myrow[[pathName]]
    myvalues <- myrow[!colnames(myrow) == pathName]
    
    #create node and ancestors if necessary (might already have been created)
    paths <- strsplit(mypath, pathDelimiter, fixed = TRUE)[[1]]
    paths <- paths[paths!=""]
    if (is.null(root)) root <- Node$new(paths[1])
    mynode <- root
    colsToSet <- mycols
    colsToSetForLeaf <- mycols
    for (path in paths[-1]) {
      child <- mynode$Find(path)
      
      if( is.null(child)) {
        mynode <- mynode$AddChild(path)
      } else {
        mynode <- child
      }
      
      if( length(colLevels) >= mynode$level ) {
        colsToSet <- intersect(colLevels[[mynode$level]], mycols) 
        
        #fill values on appropriate level
        for (mycol in colsToSet) {
          if ( !( na.rm && is.na(myrow[[mycol]]) )) {
            mynode[[mycol]] <- myrow[[mycol]]
          }
        }
        colsToSetForLeaf <- colsToSetForLeaf[!(colsToSetForLeaf %in% colsToSet)]
      }
      
    }
    
    #put the rest in the leaf
    for (mycol in colsToSetForLeaf) {
      if ( !( na.rm && is.na(myrow[[mycol]]) )) {
        mynode[[mycol]] <- myrow[[mycol]]
      }
      #remove
    }    
    
    
  }
  return (root)
}

