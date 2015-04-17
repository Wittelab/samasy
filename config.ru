require 'rubygems'
require 'sinatra'
# Database files
require 'data_mapper'
require 'dm-sqlite-adapter'
require 'json'
# User Auth
require 'bcrypt'
require 'warden'
# Key/value store
require 'daybreak'
require 'securerandom'
# Template engines
require 'slim'
require 'sass'


### Run Environment Configuration
configure :development do
	require 'pry-debugger'
	#DataMapper::Logger.new(STDOUT, :debug)
end

configure :production do
	set :environment, ENV['RACK_ENV'].to_sym
	set :app_file, 'main.rb'
	disable :run
end



### Use sessions
#enable :sessions
# Used instead of 'enable :sessions' above because of session clear on post issue
use Rack::Session::Cookie, :key => 'samasy', :path => '/', :expire_after => 14400, :secret => 'secret_secret'



### Setup Datamapper
#DataMapper.setup(:default, ENV['DATABASE_URL'] || 'mysql://samasy:platedb@localhost/samasy')
DataMapper.setup(:default, ENV['DATABASE_URL'] || 'sqlite:db/samasy.db')



### Setup Warden
use Warden::Manager do |config|
	config.serialize_into_session{|user| user.id }
	config.serialize_from_session{|id| User.get(id) }
	config.scope_defaults :default,
		strategies: [:password],
		action: 'auth/unauthenticated'
	config.failure_app = App
end

Warden::Manager.before_failure do |env,opts|
	env['REQUEST_METHOD'] = 'POST'
end

Warden::Strategies.add(:password) do
	def valid?
		params['username'] && params['password']
	end

	def authenticate!
		user = User.first(username: params['username'])

		if user.nil?
			fail!("The username you entered does not exist.")
		elsif user.authenticate(params['password'])
			success!(user)
		else
			fail!("Could not log in")
		end
	end
end



### Add other required files
require './db'
require './main'

### And start the app!
run App
