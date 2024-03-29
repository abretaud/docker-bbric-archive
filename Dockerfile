FROM debian:bullseye
MAINTAINER Anthony Bretaudeau <anthony.bretaudeau@inrae.fr>

ADD perl_modules.txt /root/perl_modules.txt

# Install deps
RUN apt-get -q update && \
    DEBIAN_FRONTEND=noninteractive apt-get -yq --no-install-recommends install \
    apache2 libapache2-mod-perl2 postgresql-client-13 curl file libdbi-perl libdbd-pg-perl tree libxml-twig-perl libjson-perl xsltproc \
    libconvert-uulib-perl at liblog-log4perl-perl liblog-dispatch-filerotate-perl nano subversion git patch libxml2-utils ssmtp mailutils \
    xz-utils bzip2 sqlite3 cron && \
    BUILD_DEPS="build-essential" && \
    DEBIAN_FRONTEND=noninteractive apt-get -yq --no-install-recommends install $BUILD_DEPS \
    && curl -L http://cpanmin.us | perl - --self-upgrade \
    && for x in $(cat /root/perl_modules.txt); do cpanm --notest $x; done \
    && apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false -o APT::AutoRemove::SuggestsImportant=false $BUILD_DEPS \
    && rm -rf /var/lib/apt/lists/* \
    && ln -s /usr/bin/mail /usr/bin/Mail

ENV TINI_VERSION v0.9.0
RUN set -x \
    && curl -fSL "https://github.com/krallin/tini/releases/download/$TINI_VERSION/tini" -o /usr/local/bin/tini \
    && chmod +x /usr/local/bin/tini

ENTRYPOINT ["/usr/local/bin/tini", "--"]

COPY apache2-foreground /usr/local/bin/

RUN sed -i.bak '/www-data/d' /etc/at.deny

RUN a2enmod -f rewrite \
    && a2dismod -f deflate

ADD etc/ssmtp/ssmtp.conf /etc/ssmtp/ssmtp.conf

WORKDIR /var/www/html

ADD findbin.patch /opt/findbin.patch
ADD ext_ftp.patch /opt/ext_ftp.patch
ADD fix_auth.patch /opt/fix_auth.patch
ADD nodebug.patch /opt/nodebug.patch

RUN svn co http://lipm-svn.toulouse.inra.fr/svn/inra_archive/tags/archive_v2.0 . && \
    rm -rf .svn doc && \
    patch -p1 < /opt/findbin.patch && \
    patch -p1 < /opt/ext_ftp.patch && \
    patch -p1 < /opt/fix_auth.patch && \
    patch -p1 < /opt/nodebug.patch && \
    git clone https://lipm-gitlab.toulouse.inra.fr/LIPM-BIOINFO/ezlastic.git bin/ext/ezlastic && \
    cd bin/ext/ezlastic && \
    git checkout 54369ce3acdc94aa67950e2765c0229defab6d8d && \
    cd ../../.. && \
    chown -R www-data: .

ADD site/cfg/install.cfg /var/www/html/site/cfg/install.cfg
ADD site/cfg/externaltool.hosts /var/www/html/site/cfg/externaltool.hosts

# tests are expected to fail...
RUN ./install.pl || echo ""

# Run the miniclient every hour
RUN echo "0 * * * * (bash -lc 'perl /opt/miniclient/miniclient.pl >> /var/log/archive_miniclient.log 2>&1') > /dev/null 2>&1 || true" >> /tmp/client_cron && \
    crontab /tmp/client_cron && rm /tmp/client_cron

# Keep a backup of config files with placeholders
RUN cp /var/www/html/site/cfg/archive.cfg /var/www/html/site/cfg/archive.cfg.docker_template
ADD site/cfg/apache.cfg.docker_template /var/www/html/site/cfg/apache.cfg.docker_template

ADD archive_apache.conf /etc/apache2/conf-enabled/archive.conf.template

ADD miniclient/miniclient.pl /opt/miniclient/miniclient.pl

ENV ARCHIVE_HTTP_HOST=https://localhost
ENV ARCHIVE_HTTP_ROOT=
ENV ARCHIVE_TITLE="BBRIC Archive"
ENV ARCHIVE_FTP=your.ftp.site
ENV ARCHIVE_EXT_FTP=

ADD entrypoint.sh /

CMD ["/entrypoint.sh"]
