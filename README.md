# autoparallel

_experimental library to transform serial R code into parallel_

If you would like to write parallel R today then you should start with a
well established package. The CRAN Task View: [High-Performance and
Parallel Computing with
R](https://cran.r-project.org/web/views/HighPerformanceComputing.html)
provides a comprehensive review of available software.
[parallel](https://stat.ethz.ch/R-manual/R-devel/library/parallel/doc/parallel.pdf),
included with R since R 2.14, provides the core functionality to do
multiprocessing.
[foreach](https://cran.r-project.org/web/packages/foreach/index.html) and
[futures](https://cran.r-project.org/web/packages/future/index.html) are
CRAN packages that offer additional abstractions.

## high level

The main idea is to transform serial R programs written in base R into
parallel programs. This automatic program tranformation differs from
current parallel technologies which require the user to explicitly write
code for a given parallel programming model.

Opportunities for parallelism are found through analysis of base R's apply
family of functions using the [CodeDepends
package](https://cran.r-project.org/web/packages/CodeDepends/index.html)
The apply family includes \texttt{lapply, apply, sapply, tapply, by,
mapply, Map, vapply, outer, by, replicate}. These are all variants of the
map reduce computational model which has been successful for implementing
large scale parallel systems.

Performance profiling measures how long the program spends executing each
part of the code. The profiling together with estimates of the overhead on
the particular machine allow us to determine if it's actually worth it to
parallelize a given R expression.  If the parallel version is slower then
the expression should be left in serial form.

The broader goal is to incorporate more intelligence into the system,
freeing the user to write higher level code that also performs better.

## examples

See the vignettes in this package, or look in `inst/examples`.
