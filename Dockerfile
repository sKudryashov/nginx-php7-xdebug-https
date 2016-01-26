FROM debian:8.2
MAINTAINER s.a.kudryashov@gmail.com

#WGET, CURL, PEAR, PHING, MC, VIM, LOCATE, SUPERVISOR installation
RUN apt-get update -y && apt-get upgrade -y
RUN apt-get install -y apt-utils
RUN apt-get update -y && apt-get install --no-install-recommends -y -q curl build-essential ca-certificates git
RUN apt-get install php-pear -y && pear channel-update pear.php.net && pear upgrade pear && \
    pear channel-discover pear.phing.info && pear install --alldeps phing/phing
RUN apt-get install -y mc vim wget locate supervisor sudo

ENV DEBIAN_FRONTEND noninteractive

#let's install geaman server and client
RUN apt-get install -y gearman gearman-job-server gearman-tools libgearman-dev libgearman7

#PHP additional packages installation

RUN apt-get -y upgrade &&  apt-get install -y \
      unzip \
      libxml2 \
      libcurl4-openssl-dev \
      sqlite3 libsqlite3-dev vim mc

# Clone the PHP source repository
#RUN cd /tmp && wget http://pl1.php.net/get/php-7.0.2.tar.bz2/from/this/mirror
#RUN tar -xvzf php-7.0.2.tar.bz2 /usr/local/src/php
RUN git clone https://github.com/php/php-src.git /usr/local/src/php
ADD ./assets/php /tmp/php-repository
RUN cd /tmp/php-repository && tar -xvf php-7.0.2.tar.bz2 && cp -R ./php-7.0.2/* /usr/local/src/php
# Compile PHP7 right now to bootstrap everything else
RUN apt-get -y install autoconf re2c bison libxml2-dev libssl-dev && cd /usr/local/src/php && ./configure \
    --prefix=/usr/local/php70 \
    --with-config-file-path=/usr/local/php70 \
    --with-config-file-scan-dir=/usr/local/php70/conf.d \
    --with-mysql-sock=/var/run/mysqld/mysqld.sock \
    --with-libdir=/lib/x86_64-linux-gnu \
    --enable-fpm \
    --with-pear \
    --with-openssl \
    --with-curl \
    --enable-soap \
    --enable-cgi \
    --enable-ftp \
    --with-xmlrpc \
    --enable-fpm \
    --enable-xmlreader \
    --with-mysqli=mysqlnd \
    --enable-phpdbg \
    --enable-calendar \
    --enable-bcmath \
    --with-imap-ssl --with-pdo-mysql=mysqlnd
RUN cd /usr/local/src/php && make
RUN cd /usr/local/src/php && make install

# Set up Rasmus's handy PHP scripts
COPY makephp /usr/bin/makephp
COPY newphp /usr/bin/newphp

RUN chmod +x /usr/bin/makephp /usr/bin/newphp

RUN ln -s /usr/local/php70/bin/phpize /usr/bin/phpize
RUN rm -rf /usr/bin/php && ln -s /usr/local/php70/bin/php /usr/bin/php

RUN	cd /usr/local/src/php && \
    cp /usr/local/src/php/php.ini-production /usr/local/php70/php.ini && \
    cp /usr/local/php70/etc/php-fpm.conf.default /usr/local/php70/etc/php-fpm.conf && \
    rm /usr/local/php70/etc/php-fpm.conf.default && \
    cp /usr/local/php70/etc/php-fpm.d/www.conf.default /usr/local/php70/etc/php-fpm.d/www.conf && \
    rm /usr/local/php70/etc/php-fpm.d/www.conf.default

#install xdebug
ADD assets/xdebug-2.4.0rc3 /tmp/xdebug-2.4.0rc3
RUN cd /tmp/xdebug-2.4.0rc3/xdebug-2.4.0RC3 && phpize && ./configure --with-php-config=/usr/local/php70/bin/php-config \
 && make && make install
#RUN cp /tmp/xdebug-2.4.0rc3/xdebug-2.4.0RC3/modules/xdebug.so /usr/local/php70/conf.d
#Xdebug path in system: /usr/local/php70/lib/php/extensions/no-debug-non-zts-20151012/xdebug.so
RUN mkdir /usr/local/php70/conf.d && touch /usr/local/php70/conf.d/xdebug.ini

#install php composer globally
RUN  curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
#install phpunit globally
RUN wget https://phar.phpunit.de/phpunit.phar && chmod +x phpunit.phar && sudo mv phpunit.phar /usr/local/bin/phpunit \
   && rm -rf phpunit.phar
#install symfony framework globally
RUN curl -LsS http://symfony.com/installer -o /usr/local/bin/symfony && curl -LsS http://symfony.com/installer -o /usr/local/bin/symfony

##########################NGINX part############################
RUN wget http://nginx.org/keys/nginx_signing.key && apt-key add nginx_signing.key && \
    echo 'deb http://nginx.org/packages/debian/ jessie nginx' >> /etc/apt/sources.list && \
    echo 'deb-src http://nginx.org/packages/debian/ jessie nginx' >> /etc/apt/sources.list && \
    apt-get update -y && apt-get install -y nginx

ADD assets/nginx/nginx.conf /etc/nginx/nginx.conf
ADD assets/nginx/server /etc/nginx/server
ADD assets/nginx/conf.d /etc/nginx/conf.d
ADD assets/php-test/index.php /usr/share/nginx/html/
RUN chown -R nginx:nginx /etc/nginx/
RUN usermod -a -G root nginx && usermod -a -G adm nginx && chmod g+w /var/log/nginx/ \
 && chmod g+w /var/log/nginx/access.log && chmod g+w /var/log/nginx/error.log \
 && usermod -a -G root www-data && usermod -a -G adm www-data && chmod 0777 /tmp
#RUN ln -sf /dev/stdout /var/log/nginx/access.log && ln -sf /dev/stderr /var/log/nginx/error.log

# Supervisor Config
ADD assets/supervisord.conf /etc/supervisord.conf
RUN echo 'root:000999' | chpasswd
RUN apt-get install -y nano
################################################################

###############################SSH##############################
RUN apt-get install -y openssh-server
RUN mkdir /var/run/sshd
RUN sed -i 's/PermitRootLogin without-password/PermitRootLogin yes/' /etc/ssh/sshd_config
RUN sed 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' -i /etc/pam.d/sshd
ENV export NOTVISIBLE="in users profile"
RUN echo "export VISIBLE=now" >> /etc/profile
ADD assets/ssh/ssh_host_dsa_key /etc/ssh/ssh_host_dsa_key
ADD assets/ssh/ssh_host_dsa_key.pub /etc/ssh/ssh_host_dsa_key.pub
ADD assets/ssh/ssh_host_ecdsa_key /etc/ssh/ssh_host_ecdsa_key
ADD assets/ssh/ssh_host_ecdsa_key.pub /etc/ssh/ssh_host_ecdsa_key.pub
ADD assets/ssh/ssh_host_ed25519_key /etc/ssh/ssh_host_ed25519_key
ADD assets/ssh/ssh_host_ed25519_key.pub /etc/ssh/ssh_host_ed25519_key.pub
ADD assets/ssh/ssh_host_rsa_key /etc/ssh/ssh_host_rsa_key
ADD assets/ssh/ssh_host_rsa_key.pub /etc/ssh/ssh_host_rsa_key.pub
RUN cd /etc/ssh/ && chmod 644 $(ls | grep .pub) && chmod 600 moduli && chmod 644 ssh_config \
    && chmod 600 ssh_host_dsa_key && chmod 600 ssh_host_ecdsa_key && chmod 600 ssh_host_rsa_key \
    && chmod 600 ssh_host_ed25519_key && chmod 640 sshd_config
RUN sed -i 's/PermitEmptyPasswords no/PermitEmptyPasswords yes/' /etc/ssh/sshd_config
################################################################


#######################Tweaking config part#####################

####PHP########
RUN sed -i -e 's/;daemonize = yes/daemonize = no/g' /usr/local/php70/etc/php-fpm.conf
RUN sed -i -e 's/user = nobody/user = www-data/g' /usr/local/php70/etc/php-fpm.d/www.conf
RUN sed -i -e 's/group = nobody/group = www-data/g' /usr/local/php70/etc/php-fpm.d/www.conf
RUN sed -i -e 's/display_errors = Off/display_errors = On/g' /usr/local/php70/php.ini
RUN sed -i -e 's/display_startup_errors = Off/display_startup_errors = On/g' /usr/local/php70/php.ini
RUN sed -i -e 's/error_reporting = E_ALL & ~E_DEPRECATED & ~E_STRICT/error_reporting = E_ALL/g' /usr/local/php70/php.ini
RUN sed -i -e 's/;error_log = syslog/error_log = /var/log/php_errors.log/g' /usr/local/php70/php.ini
#RUN sed -i -e 's/?????log_errors = ????/log_errors = On/g' /usr/local/php70/php.ini
RUN sed -i -e 's/;error_log = log\/php-fpm.log\/error_log = \/var\/log\/php-fpm.log/g' /usr/local/php70/etc/php-fpm.conf
RUN sed -i -e 's/;log_level = notice/log_level = notice/g' /usr/local/php70/etc/php-fpm.conf
RUN touch /var/log/php_errors.log && chmod 0664 /var/log/php_errors.log
RUN touch /var/log/php-fpm.log && chmod 0664 /var/log/php-fpm.log

####Xdebug#####
#RUN sed -i -e '1 a\zend_extension="/usr/local/php70/lib/php/extensions/no-debug-non-zts-20151012/xdebug.so"' /usr/local/php70/conf.d/xdebug.ini
#RUN sed -i -e "2 a\xdebug.coverage_enable=1" /usr/local/php70/conf.d/xdebug.ini
#RUN sed -i -e "3 a\xdebug.idekey=PHPSTORM" /usr/local/php70/conf.d/xdebug.ini
#RUN sed -i -e "4 a\xdebug.remote_connect_back=1" /usr/local/php70/conf.d/xdebug.ini
#RUN sed -i -e "5 a\xdebug.remote_enable=1" /usr/local/php70/conf.d/xdebug.ini
#RUN sed -i -e "6 a\xdebug.remote_port=9001" /usr/local/php70/conf.d/xdebug.ini
#RUN sed -i -e "7 a\xdebug.var_display_max_depth=300" 01672bc38da3c7340bd6f1dfa58a4008f173b73xdebug.ini
ADD assets/php/xdebug.ini /usr/local/php70/conf.d/xdebug.ini
RUN chmod a+r /usr/local/php70/conf.d/xdebug.ini && chmod a+x /usr/local/php70/conf.d/xdebug.ini

#################################################################

ADD assets/launch.sh launch.sh
RUN chmod g+x launch.sh && ln -s /launch.sh /usr/bin/launch

EXPOSE 9000
EXPOSE 9090
EXPOSE 9001
EXPOSE 443
EXPOSE 80
EXPOSE 22
#VOLUME "/usr/share/nginx/html"
ENTRYPOINT ["/usr/bin/launch"]
WORKDIR "/usr/share/nginx/html"