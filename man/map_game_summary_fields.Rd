% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/st_game_summary.R
\name{map_game_summary_fields}
\alias{map_game_summary_fields}
\title{Map Game Summary Field Names}
\usage{
map_game_summary_fields(data, os)
}
\arguments{
\item{data}{Tibble. Data with abbreviated field names.}

\item{os}{Character string. Operating system to determine mappings.}
}
\value{
Tibble with descriptive field names.
}
\description{
Internal function to map abbreviated API field names to descriptive names.
}
\keyword{internal}
