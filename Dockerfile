FROM ruby:2.0

MAINTAINER Clint Cario, https://github.com/ccario83

# Create a user to run samasy
RUN useradd -ms /bin/bash samasy

# Install required system packages
RUN apt-get update
RUN apt-get install -q -y \
	build-essential \
	gnupg \
	git \
	libsqlite3-dev \
	curl \
	zlib1g-dev \
	openssl \
	libssl-dev

# Install samasy gems
USER samasy
WORKDIR /home/samasy
#RUN gpg --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB && \
#	\curl -sSL https://get.rvm.io | bash -s stable && \
#	/bin/bash -l -c "source $HOME/.rvm/scripts/rvm"
#RUN /bin/bash -l -c "rvm autolibs disable && rvm list && rvm install 2.0"

USER samasy
WORKDIR /home/samasy
RUN /bin/bash -l -c "gem install bundler --version 1.16.3"
RUN /bin/bash -l -c "gem install --source 'https://rubygems.org/' \
	'bcrypt:3.1.12' \
	'json:1.8.6' \
	'sqlite3:1.3.9'"


# Pull the code and bundle
RUN git clone https://github.com/wittelab/samasy.git && \
	cd samasy && bundle

# Make port 9292 available to access the interface
EXPOSE 9292

# Start samasy
CMD rackup