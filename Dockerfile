FROM ruby:2.0

MAINTAINER Clint Cario, https://github.com/ccario83

# Create a user to run samasy
RUN useradd -ms /bin/bash samasy

# Install required system packages
RUN apt-get update
RUN apt-get install -q -y \
	build-essential \
	git \
	libsqlite3-dev \
	curl \
	zlib1g-dev \
	openssl \
	libssl-dev

USER samasy
WORKDIR /home/samasy
RUN /bin/bash -l -c "gem install bundler --version 1.16.3"
RUN /bin/bash -l -c "gem install --source 'https://rubygems.org/' \
	'bcrypt:3.1.12' \
	'json:1.8.6' \
	'sqlite3:1.3.9'"

# Pull the code and bundle
#RUN git clone https://github.com/wittelab/samasy.git && \
COPY --chown=samasy . .
RUN bundle

EXPOSE 9000

CMD ["bundle", "exec", "rackup", "--host", "0.0.0.0", "-p", "9000"]
