# Docker image for CATI BBRIC Archive

A Docker image for [CATI BBRIC Archive](http://bbric.toulouse.inra.fr/)

## Running it

Adapt the docker-compose.yml file to your needs, and then run:

```
docker-compose up
```

## Idiosyncrasy

This was written with BIPAA use case in mind, here are BIPAA-specific behaviors:

 - with ARCHIVE_EXT_FTP option enabled (see below), the archive will consider that the FTP service is provided outside, in the same way as it is done for Galaxy. If you don't have such FTP, disable the option and you're on your own to set up an FTP server as described in the Archive doc.
 - a client is launched every hour to generate a human-readable tree, without taking care of access permissions. Take care not to make this tree accessible for non-admin users.
 - this is intended to be used with an external proxy properly configured for shibboleth authentication. On this proxy, you should only have to add config like this:

```
<Location "/archive" >
   AuthType shibboleth
   ShibRequireSession Off
   ShibExportAssertion On
   ShibUseHeaders On
   require Shibboleth

   ProxyPass http://your-docker-host:5000/archive2
   ProxyPassReverse http://your-docker-host:5000/archive2
</location>
```

Some patches are applied:

 - ext_ftp.patch: allow to modify the Archive behavior when ARCHIVE_EXT_FTP is enabled.
 - findbin.patch: fixes some strange errors related to perl lib imports
 - fix_auth.patch: some tweaks to allow authentication with shibboleth + fix problems of 302 redirections on a POST request (proxies don't like it)

## Configuration

All the rawseq data managed by the Archive is stored in the /data directory.
You can mount the following volumes:

```
/data/store/ Stores the archive content
/data/ftp/ Stores the FTP content (can be mounted as read-only)
/data/http/ Stores data uploading from web form
/data/http_tmp/ Stores temp files for http server, nothing important here
/data/client/ Stores symbolic links created by the archive client (scheduled in crontab)
```

It is a good idea to backup these directory (particularly /data/store). You should also backup the /var/lib/postgresql/9.4/ volume from the db docker.

For example (just backup /archive):

```
version: '2'
services:

    web:
    [...]
      volumes:
        - /archive/data/:/data
       	- /galaxy/ftp_server/:data/ftp:ro
        [...]

    db:
        [...]
      volumes:
        - /archive/db:/var/lib/postgresql/9.4/
[...]
```

## Loading data from another instance

You need to backup the other SQL db, and then load it into the postgres docker.
The SQL dump contains absolute path to files, so you will probably need to change them before loading it into postgres.

```
pg_dump -c -h db_host -U db_user db_name > dirty_old_dump.sql
sed 's|/old/archive/path/|/data/store/|g' dirty_old_dump.sql > data/clean_old_dump.sql
sed -i 's|old-owner|postgres|g' data/clean_old_dump.sql # If the db owner was not postgres
docker exec -it yourdir_web_1 bash
    psql -h postgres -U postgres postgres < /data/clean_old_dump.sql
    psql -h postgres -U postgres postgres < site/sql/archive_update.v1.sql  # If updating from archive v1 to v2
    rm /data/clean_old_dump.sql
```

You also need to mount the /data dir from the original location (or copy the files if you prefer).

And finally to index using elastic:

```
bin/ext/ezlastic/bin/int/ES.idx.xml.pl \
	  --create_index \
	  --store_url=http://elasticsearch:9200/archive/sequence \
	  --parser_cfg=site/cfg/idx.sequence.cfg \
	  --input=/data/store/sequence/ \
	  --verbose
```

Also to update file size if upgrading from archive v1 to v2:

```
perl bin/int/admin_database.pl --cfg site/cfg/archive.cfg --file_size
```

## Customizing

### Environment variables

```
ARCHIVE_HTTP_HOST=https://example.org/ # The scheme+host to use (don't forget the trailing slash)
ARCHIVE_HTTP_ROOT=archive # The url prefix to append to ARCHIVE_HTTP_HOST if the Archive is not at the root
ARCHIVE_TITLE=BIPAA Archive # Name of the site
ARCHIVE_FTP=bipaa-galaxy.genouest.org # Url of the FTP site
ARCHIVE_EXT_FTP=1 # Add this if you're using an external FTP configured like galaxy (user email used for dir names mainly). No FTP server is provided otherwise.
ARCHIVE_CLIENT_MOUNTPOINT=/data/store # Used by the client to create symlinks, change this if /data/store is mounted at a different mountpoint on external servers
ARCHIVE_ADMINS=someone@example.org;somebody@example.org # ;-separated list of emails of admin
```

### Config files

Modify `site/cfg/externaltool.hosts` to allow external servers to access data (usually Galaxy servers)

Modify `/etc/ssmtp/ssmtp.conf` to configure the (external) SMTP server to be used by Archive.
