# geo-report-gen toolchain: R, the locked package library, Quarto and the system libraries they
# need. The project checkout is mounted at /app at run time (see compose.yaml), so code, config,
# content, .env, cache/ and reports/ are always the host's own files.
FROM rocker/r-ver:4.6.1

# System libraries for sf (GDAL, GEOS, PROJ, udunits), s2 (abseil), fs (libuv), ragg and
# textshaping (fonts), curl and openssl. Noto Sans is the fallback chart font: the default
# theme's Segoe UI is Windows-only.
RUN apt-get update && apt-get install -y --no-install-recommends \
      libgdal-dev libgeos-dev libproj-dev libudunits2-dev libabsl-dev libuv1-dev \
      libfontconfig1-dev libfreetype6-dev libharfbuzz-dev libfribidi-dev \
      libpng-dev libjpeg-dev libtiff-dev libwebp-dev libcurl4-openssl-dev libssl-dev \
      fonts-noto-core curl ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Quarto (includes Typst for PDF output)
ARG QUARTO_VERSION=1.9.38
RUN curl -fsSL -o /tmp/quarto.deb "https://github.com/quarto-dev/quarto-cli/releases/download/v${QUARTO_VERSION}/quarto-${QUARTO_VERSION}-linux-$(dpkg --print-architecture).deb" \
 && dpkg -i /tmp/quarto.deb && rm /tmp/quarto.deb

# R packages exactly as in renv.lock, as Linux binaries from Posit Package Manager. The library
# lives outside /app so the mounted checkout does not hide it.
WORKDIR /app
ENV RENV_PATHS_LIBRARY=/opt/renv/library \
    RENV_CONFIG_REPOS_OVERRIDE=https://p3m.dev/cran/__linux__/noble/latest \
    RENV_CONFIG_CACHE_ENABLED=FALSE
COPY renv.lock .Rprofile ./
COPY renv/activate.R renv/settings.json renv/
RUN Rscript -e "renv::restore(prompt = FALSE)"

# gr.R preview serves here (published by compose.yaml)
ENV GR_PREVIEW_PORT=4848
ENTRYPOINT ["Rscript", "gr.R"]
CMD ["help"]
