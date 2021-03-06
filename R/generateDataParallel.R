# The following methods for the platform = "ParallelLocalCluster" are designed to work together.
# I'm not thinking about name collisions at all right now.
# 
# The pattern with most of the generate methods on the CodeBlock's is to write down a quoted expression as a template
# This is better using strings for templates because R only needs to parse them once, and we catch parse errors early.
# It's better than using external template files, because we can keep all this code in one place (this file) so it's easy to find.

# TODO: Use as.expression(quote( rather than empty functions


#' @export
setMethod("generate", signature(schedule = "DataParallelSchedule", platform = "ParallelLocalCluster", data = "ANY"),
function(schedule, platform, data, ...)
{
# Idea:
# We can generate all the code independently for each block, and then just stick it all together to make the complete program.
# Assuming it's all R code, of course.
    newcode = lapply(schedule@blocks, generate, platform = platform, data = data, ...)
    newcode = do.call(c, newcode)
    GeneratedCode(schedule = schedule, code = newcode)
})


TEMPLATE_ParallelLocalCluster_InitBlock = as.expression(quote({
    message(`_MESSAGE`)

    `_FUNCTION_DEFS`

    library(parallel)

    assignments = `_ASSIGNMENT_INDICES`
    nWorkers = `_NWORKERS`

    `_CLUSTER_NAME` = makeCluster(nWorkers, type = `_CLUSTER_TYPE`)

    # TODO: This is a hack until we have a more robust way to specify and infer combining functions.
    # It will break code that tries to use the list method for c() on a data.frame
    c.data.frame = rbind

    clusterExport(`_CLUSTER_NAME`, `_FUNCTION_NAMES`)
    clusterExport(`_CLUSTER_NAME`, c("assignments", "c.data.frame"))
    parLapply(cls, seq(nWorkers), function(i) assign("workerID", i, globalenv()))

    clusterEvalQ(`_CLUSTER_NAME`, {
        assignments = which(assignments == workerID)
        NULL
    })
}))


setMethod("generate", signature(schedule = "InitBlock", platform = "ParallelLocalCluster", data = "ChunkDataFiles"),
function(schedule, platform, data
        , message = sprintf("This code was generated from R by makeParallel version %s at %s", packageVersion("makeParallel"), Sys.time())
        , template = TEMPLATE_ParallelLocalCluster_InitBlock
        , cluster_type = "PSOCK"
        , ...){
    substitute_language(template, `_MESSAGE` = message
        , `_NWORKERS` = platform@nWorkers
        , `_ASSIGNMENT_INDICES` = schedule@assignmentIndices
        , `_CLUSTER_NAME` = as.symbol(platform@name)
        , `_FUNCTION_DEFS` = schedule@code
        , `_FUNCTION_NAMES` = schedule@funcNames
        , `_CLUSTER_TYPE` = cluster_type
        )
})


setMethod("generate", signature(schedule = "InitBlock", platform = "UnixPlatform", data = "ChunkDataFiles"),
function(schedule, platform, data, ...){
    callNextMethod(schedule, platform, data, cluster_type = "FORK", ...)
})


TEMPLATE_ParallelLocalCluster_DataLoadBlock = as.expression(quote(
{
    clusterEvalQ(`_CLUSTER_NAME`, {
        read_args = `_READ_ARGS`
        read_args = read_args[assignments]
        chunks = lapply(read_args, `_READ_FUNC`)
        `_DATA_VARNAME` = do.call(`_COMBINE_FUNC`, chunks)
        NULL
    })
}))


setMethod("generate", signature(schedule = "DataLoadBlock", platform = "ParallelLocalCluster", data = "ChunkDataFiles"),
function(schedule, platform, data
         , combine_func = as.symbol("c") # TODO: Use rbind if it's a data.frame
         , read_func = as.symbol(data@readFuncName)
         , template = TEMPLATE_ParallelLocalCluster_DataLoadBlock
         , ...){
    substitute_language(template, `_CLUSTER_NAME` = as.symbol(platform@name)
        , `_READ_ARGS` = data@files
        , `_READ_FUNC` = read_func
        , `_DATA_VARNAME` = as.symbol(data@varName)
        , `_COMBINE_FUNC` = combine_func
        )
})


TEMPLATE_read_chunk_func_body = as.expression(quote(
    function(x) `_READ_FUNC`(x
            , col.names = `_COL.NAMES`
            , colClasses = `_COLCLASSES`
            , header = `_HEADER`
            , sep = `_SEP`
            )
))


TEMPLATE_split_on_disk = quote({
    nlines = system2("wc", c("-l", `_DATA_FILE_NAME`), stdout = TRUE)
    nlines = regmatches(nlines, regexpr("[0-9]+", nlines))
    nlines = as.integer(nlines)
    lines_per_file = ceiling(nlines / `_NWORKERS`)
    chunk_file_dir = paste0("chunk_", `_DATA_FILE_NAME`)
    dir.create(chunk_file_dir, showWarnings = FALSE)

    system2("split", c("-l", lines_per_file, `_DATA_FILE_NAME`, paste0(chunk_file_dir, "/")))
    chunk_files = list.files(chunk_file_dir, full.names = TRUE)

    clusterExport(`_CLUSTER_NAME`, "chunk_files")

    clusterEvalQ(`_CLUSTER_NAME`, {
        read_arg = chunk_files[workerID]
        `_DATA_VARNAME` = `_READ_FUNC`(read_arg)
        NULL
    })
})


TEMPLATE_UnixPlatform_DataLoadBlock_TextTableFiles = quote({
    nlines = system2("wc", c("-l", `_DATA_FILE_NAME`), stdout = TRUE)
    nlines = regmatches(nlines, regexpr("[0-9]+", nlines))
    nlines = as.integer(nlines)

    lines_per_worker = makeParallel:::even_splits(nlines, `_NWORKERS`)
    skip_per_worker = c(0, cumsum(lines_per_worker[-length(lines_per_worker)]))

    clusterExport(`_CLUSTER_NAME`, c("lines_per_worker", "skip_per_worker"))

    clusterEvalQ(`_CLUSTER_NAME`, {
        `_DATA_VARNAME` = data.table::fread(`_DATA_FILE_NAME`
            , nrows = lines_per_worker[workerID]
            , skip = skip_per_worker[workerID]
            , nThread = 1L
            )
        # Convert back to data frame by reference:
        data.table::setDF(`_DATA_VARNAME`)
        NULL
    })
})


setMethod("generate", signature(schedule = "DataLoadBlock", platform = "UnixPlatform", data = "TextTableFiles"),
function(schedule, platform, data, template = TEMPLATE_UnixPlatform_DataLoadBlock_TextTableFiles, ...)
{
    if(length(data@files) == 1){
    substitute_language(template
        , `_DATA_FILE_NAME` = data@files
        , `_NWORKERS` = platform@nWorkers
        , `_CLUSTER_NAME` = as.symbol(platform@name)
        , `_DATA_VARNAME` = as.symbol(data@varName)
        )
    } else {
        callNextMethod(schedule, platform, data, ...)
    }
})


setMethod("generate", signature(schedule = "DataLoadBlock", platform = "ParallelLocalCluster", data = "TextTableFiles"),
function(schedule, platform, data
         , combine_func = as.symbol("rbind")
         , template = TEMPLATE_read_chunk_func_body
         , read_func = substitute_language(template
                , `_READ_FUNC` = as.symbol(data@readFuncName)
                , `_COL.NAMES` = data@col.names
                , `_COLCLASSES` = data@colClasses
                , `_HEADER` = data@header
                , `_SEP` = data@sep
                )
         , ...){

    callNextMethod(schedule, platform, data, read_func = read_func, combine_func = combine_func)
})


TEMPLATE_ParallelLocalCluster_SerialBlock = function()
{
    collected = clusterEvalQ(`_CLUSTER_NAME`, {
        `_OBJECTS_RECEIVE_FROM_WORKERS`
    })

    # Unpack and assemble the objects
    vars_to_collect = names(collected[[1]])
    for(i in seq_along(vars_to_collect)){
        varname = vars_to_collect[i]
        chunks = lapply(collected, `[[`, i)
        value = do.call(`_COMBINE_FUNC`, chunks)
        assign(varname, value)
    }
}

setMethod("generate", signature(schedule = "SerialBlock", platform = "ParallelLocalCluster", data = "ANY"),
function(schedule, platform, data
         , combine_func = as.symbol("c") # TODO: Use rbind if it's a data.frame
         , template = as.expression(body(TEMPLATE_ParallelLocalCluster_SerialBlock))
         , ...){
    if(1 <= length(schedule@collect)){
        first = substitute_language(template, `_CLUSTER_NAME` = as.symbol(platform@name)
            , `_OBJECTS_RECEIVE_FROM_WORKERS` = char_to_symbol_list(schedule@collect)
            , `_COMBINE_FUNC` = combine_func
            )
    } else {
        first = expression()
    }
    c(first, schedule@code)
})


setMethod("generate", signature(schedule = "ParallelBlock", platform = "ParallelLocalCluster", data = "ANY"),
function(schedule, platform
         , export_template = parse(text = '
clusterExport(`_CLUSTER_NAME`, `_EXPORT`)
')
         , run_template = parse(text = '
clusterEvalQ(`_CLUSTER_NAME`, {
    `_BODY`
    NULL
})
'), ...){
    
    part1 = if(0 == length(schedule@export)){
        expression()
    } else {
        substitute_language(export_template, 
            `_CLUSTER_NAME` = as.symbol(platform@name)
            , `_EXPORT` = schedule@export
            )
    }

    part2 = substitute_language(run_template, `_CLUSTER_NAME` = as.symbol(platform@name)
        , `_BODY` = schedule@code
        )

    c(part1, part2)
})


TEMPLATE_ParallelLocalCluster_SplitBlock = function()
{
    # Copied and modified from ~/projects/clarkfitzthesis/Chap1Examples/range_date_by_station/date_range_par.R
    #
    # See shuffle section in clarkfitzthesis/scheduleVector for explanation and comparison of different approaches.
    # This is the naive version that writes everything out to disk.

    clusterEvalQ(`_CLUSTER_NAME`, {

    groupData = `_GROUP_DATA`
    groupIndex = `_GROUP_INDEX`

    # Write a single group out for a single worker.
    write_one = function(grp, grp_name){

        group_dir = file.path(`_SCRATCH_DIR`, `_GROUP_DATA_STRING`, grp_name)

        # Directory creation is a non-op if the directory already exists.
        dir.create(group_dir, recursive = TRUE, showWarnings = FALSE)
        path = file.path(group_dir, workerID)

        # TODO: Check if this will write over files.
        `_INTERMEDIATE_SAVE_FUNC`(grp, file = path)
    }

    s = split(groupData, groupIndex)

    Map(write_one, s, names(s))

    NULL
    })


    # Count the groups so we can balance the load
    group_counts_each_worker = clusterEvalQ(cls, table(`_GROUP_INDEX`))

    # Combine all the tables together
    add_table = function(x, y)
    {
        # Assume not all values will appear in each table
        levels = union(names(x), names(y))
        out = rep(0L, length(levels))
        out[levels %in% names(x)] = out[levels %in% names(x)] + x
        out[levels %in% names(y)] = out[levels %in% names(y)] + y
        names(out) = levels
        as.table(out)
    }

    group_counts = Reduce(add_table, group_counts_each_worker, init = table(logical()))

    # Balance the load based on how large each group is.
    # This needs to happen on the manager, because it aggregates from all workers.
    # TODO: inline or otherwise make available this greedy_assign function.
    split_assignments = makeParallel:::greedy_assign(group_counts, `_NWORKERS`)

    group_names = names(group_counts)
    split_read_args = file.path(`_SCRATCH_DIR`, `_GROUP_DATA_STRING`, group_names)
    names(split_read_args) = group_names

    read_one_group = function(group_dir)
    {
        files = list.files(group_dir, full.names = TRUE)
        group_chunks = lapply(files, `_INTERMEDIATE_LOAD_FUNC`)
        group = do.call(`_COMBINE_FUNC`, group_chunks)
    }

    clusterExport(`_CLUSTER_NAME`, c("split_assignments", "split_read_args", "read_one_group"))

    clusterEvalQ(`_CLUSTER_NAME`, {

        split_assignments = which(split_assignments == workerID)

        # Write over the global variables to make them local.
        split_read_args = split_read_args[split_assignments]

        # This will hold the *unordered* result of the split
        # TODO: Think hard about the implications of this being unordered.
        `_SPLIT_LHS` = lapply(split_read_args, read_one_group)

        # Add the names back

        NULL
    })
}

setMethod("generate", signature(schedule = "SplitBlock", platform = "ParallelLocalCluster", data = "ANY"),
function(schedule, platform
         , combine_func = as.symbol("c")
         , intermediate_save_func = as.symbol("saveRDS")
         , intermediate_load_func = as.symbol("readRDS")
         , template = as.expression(body(TEMPLATE_ParallelLocalCluster_SplitBlock))
         , ...){

    # Assumes there are not multiple variables to split by.
    # It would be a miracle if this did the right thing when groupIndex is a list.

    substitute_language(template, `_CLUSTER_NAME` = as.symbol(platform@name)
        , `_SCRATCH_DIR` = platform@scratchDir
        , `_GROUP_DATA` = as.symbol(schedule@groupData)
        , `_GROUP_DATA_STRING` = schedule@groupData
        , `_GROUP_INDEX` = as.symbol(schedule@groupIndex)
        , `_COMBINE_FUNC` = combine_func
        , `_INTERMEDIATE_SAVE_FUNC` = intermediate_save_func
        , `_INTERMEDIATE_LOAD_FUNC` = intermediate_load_func 
        , `_SPLIT_LHS` = schedule@lhs
        , `_NWORKERS` = platform@nWorkers
        )
})


TEMPLATE_ParallelLocalCluster_ReduceBlock_1 = function()
{
    clusterEvalQ(`_CLUSTER_NAME`, {
        `_SUMMARY_FUN` = `_SUMMARY_FUN_IMPLEMENTATION` 
        NULL
    })
    `_COMBINE_FUN` = `_COMBINE_FUN_IMPLEMENTATION` 
    `_QUERY_FUN` = `_QUERY_FUN_IMPLEMENTATION` 
}


TEMPLATE_ParallelLocalCluster_ReduceBlock_2 = function()
{
    `_TMP_VAR` = clusterEvalQ(`_CLUSTER_NAME`, `_SUMMARY_FUN`(`_OBJECT_TO_REDUCE`))
    `_TMP_VAR` = do.call(`_COMBINE_FUN`, `_TMP_VAR`)
    `_RESULT` = `_QUERY_FUN`(`_TMP_VAR`)
}


# Let's us handle these cases of functions:
#   1. name of a function, say "table"
#   2. name including package, say "base::table"
#   3. user implementation, say `function(x) ...`
func_name_or_implementation = function(x){
    if(is.function(x)){
        x
    } else {
        as_symbol_maybe_colons(x)
    }
}


setMethod("generate", signature(schedule = "ReduceBlock", platform = "ParallelLocalCluster", data = "ChunkDataFiles"),
function(schedule, platform, data
         , tmp_var = "tmp"
         , summaryFun_tmp_var = "summaryFun"
         , combineFun_tmp_var = "combineFun"
         , queryFun_tmp_var = "queryFun"
         , template1 = as.expression(body(TEMPLATE_ParallelLocalCluster_ReduceBlock_1))
         , template2 = as.expression(body(TEMPLATE_ParallelLocalCluster_ReduceBlock_2))
         , ...){

    rfun = schedule@reduceFun
    first = expression()

    if(is(rfun, "UserDefinedReduce")){
        # Inline the user defined implementations for the reduce.
        # This will inline them every single time they are used.
        # Another argument to generate a package...

        first = substitute_language(template1, `_CLUSTER_NAME` = as.symbol(platform@name)
            , `_SUMMARY_FUN` = as.symbol(summaryFun_tmp_var)
            , `_SUMMARY_FUN_IMPLEMENTATION` = func_name_or_implementation(rfun@summary)
            , `_COMBINE_FUN` = as.symbol(combineFun_tmp_var)
            , `_COMBINE_FUN_IMPLEMENTATION` = func_name_or_implementation(rfun@combine)
            , `_QUERY_FUN` = as.symbol(queryFun_tmp_var)
            , `_QUERY_FUN_IMPLEMENTATION` = func_name_or_implementation(rfun@query)
            )

        # Reuse the temporary variable names.
        rfun = SimpleReduce(reduce = rfun@reduce, summary = summaryFun_tmp_var
            , combine = combineFun_tmp_var, query = queryFun_tmp_var)
    }

    second = substitute_language(template2, `_CLUSTER_NAME` = as.symbol(platform@name)
        , `_OBJECT_TO_REDUCE` = as.symbol(schedule@objectToReduce)
        , `_TMP_VAR` = as.symbol(tmp_var)
        , `_SUMMARY_FUN` = as_symbol_maybe_colons(rfun@summary)
        , `_COMBINE_FUN` = as_symbol_maybe_colons(rfun@combine)
        , `_QUERY_FUN` = as_symbol_maybe_colons(rfun@query)
        , `_RESULT` = as.symbol(schedule@resultName)
    )
    c(first, second)
})


setMethod("generate", signature(schedule = "FinalBlock", platform = "ParallelLocalCluster", data = "ChunkDataFiles"),
function(schedule, platform, data
        , template = quote(stopCluster(`_CLS`)))
{
    substitute_language(template, `_CLS` = as.symbol(platform@name))
})
