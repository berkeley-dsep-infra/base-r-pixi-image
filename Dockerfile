FROM us-central1-docker.pkg.dev/ucb-datahub-2018/base-images-repo/base-python-pixi-image:0089ef7

# -------------------------------
# Environment for R
# -------------------------------

ENV R_LIBS_USER=/srv/r
ENV CONDA_DIR=/srv/conda

ENV PATH="/usr/lib/rstudio-server/bin:${CONDA_DIR}/envs/notebook/bin:${CONDA_DIR}/bin:${PATH}"

# -------------------------------
# System packages for R
# -------------------------------
USER root
COPY apt.txt /tmp/apt.txt
RUN apt-get -qq update --yes && \
    apt-get -qq install --yes --no-install-recommends \
        $(grep -v ^# /tmp/apt.txt) && \
    apt-get -qq purge && \
    apt-get -qq clean && \
    rm -rf /var/lib/apt/lists/*

# -------------------------------
# R installation
# -------------------------------
ENV R_VERSION=4.4.2

RUN wget --quiet -O /tmp/r-${R_VERSION}.deb \
    https://cdn.rstudio.com/r/ubuntu-$(. /etc/os-release && echo $VERSION_ID | sed 's/\.//')/pkgs/r-${R_VERSION}_1_amd64.deb && \
    apt-get -qq update --yes && \
    apt-get install --yes --no-install-recommends /tmp/r-${R_VERSION}.deb > /dev/null && \
    rm /tmp/r-${R_VERSION}.deb && \
    apt-get -qq purge && \
    apt-get -qq clean && \
    rm -rf /var/lib/apt/lists/* && \
    ln -s /opt/R/${R_VERSION}/bin/R /usr/local/bin/R && \
    ln -s /opt/R/${R_VERSION}/bin/Rscript /usr/local/bin/Rscript && \
    R --version

ENV R_HOME=/opt/R/${R_VERSION}/lib/R

# -------------------------------
# RStudio server installation
# -------------------------------
RUN apt-get update -qq > /dev/null && \
    if apt-cache search libssl3 | grep -q libssl3; then \
      RSTUDIO_URL="https://download2.rstudio.org/server/jammy/amd64/rstudio-server-2024.12.0-467-amd64.deb" ; \
      RSTUDIO_HASH="1493188cdabcc1047db27d1bd0e46947e39562cbd831158c7812f88d80e742b3" ; \
    else \
      RSTUDIO_URL="https://download2.rstudio.org/server/focal/amd64/rstudio-server-2024.12.0-467-amd64.deb" ; \
      RSTUDIO_HASH="052540a8df135d9ce7569ddc2fc9637671103934179691bc3e43298336fc3a8e" ; \
    fi && \
    curl --silent --location --fail "${RSTUDIO_URL}" -o /tmp/rstudio.deb && \
    curl --silent --location --fail "https://download3.rstudio.org/ubuntu-18.04/x86_64/shiny-server-1.5.22.1017-amd64.deb" -o /tmp/shiny.deb && \
    echo "${RSTUDIO_HASH} /tmp/rstudio.deb" | sha256sum -c - && \
    echo "0fa40054f038de464a26f3f8c40180a072228454762b7a12ed50568b3256c236 /tmp/shiny.deb" | sha256sum -c - && \
    apt-get install -y --no-install-recommends /tmp/rstudio.deb /tmp/shiny.deb && \
    rm -f /tmp/*.deb && \
    apt-get purge -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

USER ${NB_USER}
COPY --chown=${NB_USER}:${NB_USER} environment.yml /tmp/environment.yml

# Update existing /srv/conda/notebook environment with new packages
RUN mamba env update -n notebook -f /tmp/environment.yml && \
    mamba clean -afy && rm -rf /tmp/environment.yml

USER root
# -------------------------------
# R environment tweaks
# -------------------------------
RUN mkdir -p ${R_LIBS_USER} && chown ${NB_USER}:${NB_USER} ${R_LIBS_USER}
RUN sed -i -e '/^R_LIBS_USER=/s/^/#/' /opt/R/${R_VERSION}/lib/R/etc/Renviron && \
    echo "R_LIBS_USER=${R_LIBS_USER}" >> /opt/R/${R_VERSION}/lib/R/etc/Renviron && \
    echo "TZ=${TZ}" >> /opt/R/${R_VERSION}/lib/R/etc/Renviron


COPY Rprofile.site /opt/R/${R_VERSION}/lib/R/etc/Rprofile.site
COPY rsession.conf /etc/rstudio/rsession.conf
COPY rserver.conf /etc/rstudio/rserver.conf
COPY file-locks /etc/rstudio/file-locks

USER ${NB_USER}
RUN R -e "install.packages('IRkernel')" && \
    R -e "IRkernel::installspec(user = FALSE, prefix='${CONDA_DIR}/envs/notebook')"

# -------------------------------
# R packages
# -------------------------------
COPY install.R /tmp/install.R
RUN Rscript /tmp/install.R && rm -rf /tmp/downloaded_packages/ /tmp/*.rds

