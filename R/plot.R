#' @importFrom graphics plot
NULL

setGeneric("plot")


# Accepts and plots a single row of a data frame containing the following columns:
# - start_time
# - end_time
# - processor
# - node (optional)
# - label (optional)
plot_one_eval_block = function(row, blockHeight, rectAes, labelExpr)
{with(row, {
    rect_args = list(xleft = start_time
        , ybottom = processor - blockHeight
        , xright = end_time
        , ytop = processor + blockHeight
        )
    do.call(graphics::rect, c(rect_args, rectAes))

    if(is.null(labelExpr) || labelExpr){
        lab = if(is.null(labelExpr)) node else label
        text(x = (start_time + end_time) / 2, y = processor, labels = lab)
    }

})}


plot_one_transfer = function(row, blockHeight, rectAes, sendColor, receiveColor
                             , labelTransfer, text_adj = 1.2)
{with(row, {
    send_rect_args = list(xleft = start_time_send
        , ybottom = proc_send - blockHeight
        , xright = end_time_send
        , ytop = proc_send + blockHeight
        )
    rectAes[["col"]] = rectAes[["border"]] = sendColor
    do.call(graphics::rect, c(send_rect_args, rectAes))

    receive_rect_args = list(xleft = start_time_receive
        , ybottom = proc_receive - blockHeight
        , xright = end_time_receive
        , ytop = proc_receive + blockHeight
        )
    rectAes[["col"]] = rectAes[["border"]] = receiveColor
    do.call(graphics::rect, c(receive_rect_args, rectAes))

    delta = 1.1 * blockHeight
    adj = c(text_adj, text_adj)
    # Arrows can go up or down
    if(proc_receive > proc_send){
        delta = -delta
        adj = c(text_adj, 0)
    }
    x_send = mean(c(end_time_send, start_time_send))
    y_send = proc_send - delta
    arrows(x0 = x_send, y0 = y_send
        , x1 = mean(c(end_time_receive, start_time_receive))
        , y1 = proc_receive + delta
        )
    if(labelTransfer)
        text(x_send, y_send, varname, adj = adj)
})}


#' Gantt chart of a schedule
#'
#' @export
#' @param x \linkS4class{TaskSchedule}
#' @param blockHeight height of rectangle, between 0 and 0.5
#' @param main title
#' @param xlab x axis label
#' @param ylab y ayis label
#' @param evalColor color for evaluation blocks
#' @param sendColor color for send blocks
#' @param receiveColor color for receive blocks
#' @param labelTransfer add labels for transfer arrows
#' @param labelExpr NULL to use default numbering labels, FALSE to suppress
#' labels, or a character vector of custom labels.
#' @param rectAes list of additional arguments for
#'   \code{\link[graphics]{rect}}
#' @param ... additional arguments to \code{plot}
setMethod(plot, c("TaskSchedule", "missing"), function(x, blockHeight = 0.25, main = "schedule plot"
    , xlab = "Time (seconds)", ylab = "Processor"
    , evalColor = "gray", sendColor = "orchid", receiveColor = "slateblue"
    , labelTransfer = TRUE, labelExpr = NULL, rectAes = list(density = NA, border = "black", lwd = 2)
    , ...)
{
    run = x@evaluation

    xlim = c(min(run$start_time), max(run$end_time))
    ylim = c(min(run$processor) - 0.5, max(run$processor) + 0.5)
    plot(xlim, ylim, type = "n", yaxt = "n"
         , xlab = xlab, ylab = ylab, main = main, ...)

    graphics::axis(2, at = seq(max(run$processor)))

    if(is.character(labelExpr)){
        run$label = labelExpr
        labelExpr = TRUE
    }

    rectAes[["col"]] = evalColor
    by(run, seq(nrow(run)), plot_one_eval_block
        , blockHeight = blockHeight
        , rectAes = rectAes
        , labelExpr = labelExpr
        )

    by0(x@transfer, seq(nrow(x@transfer)), plot_one_transfer
        , blockHeight = blockHeight
        , rectAes = rectAes
        , sendColor = sendColor
        , receiveColor = receiveColor
        , labelTransfer = labelTransfer
        )

    NULL
})


#' Plot Dependency Graph
#' 
#' Produces a PDF image using graphviz
#'
#' @export
#' @param graph dependGraph
#' @param file character where to save pdf image
#' @param dotfile character where to save dot commands to produce plot
#' @param args character additional arguments to \code{dot} command line program
plotDOT = function(graph, file = NULL, dotfile = NULL, args = "")
{
    g = as(graph, "igraph")

    if(is.null(dotfile)){
        dotfile = tempfile()
        on.exit(unlink(dotfile))
    }

    igraph::write_graph(g, dotfile, format = "dot")

    if(!is.null(file)){
        allargs = c("-Tpdf", dotfile, "-o", file, args)
        system2("dot", allargs)
    }
}
