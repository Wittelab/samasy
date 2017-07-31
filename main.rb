#!/usr/bin/env ruby


# Application
class App < Sinatra::Base
	### Initialize daybreak key/value store
	keystore = Daybreak::DB.new "db/daybreak.db"
	keystore.clear()

	##############################################################################
	#                           Template Processors                              #
	##############################################################################

	#get "/js/*.js" do
	#    coffee "public/#{params[:splat].first}".to_sym
	#end

	# To handle sass
	get '/css/*.css' do
		sass :"sass/#{params[:splat].first}"
	end


	##############################################################################
	#                                Main Routes                                 #
	##############################################################################
	# 4 OH 4
	not_found do
		@message = "Page not found."
		slim :"slim/404", :layout => :"slim/layout"
	end

	# Main landing page
	get '/' do
		if Plate.first.nil?
			redirect '/start'
		else
			redirect '/plate'
		end
	end

	# The database initialization wizard
	get '/start' do
		if not Plate.first.nil?
			env['warden'].authenticate!
		end
		session.clear
		# Give a session key to allow an admin user account to be created
		key = SecureRandom.hex
		session[:auto_admin] = key
		keystore[key] = "valid"
		slim :"/slim/start"
	end


	get '/samples' do
		env['warden'].authenticate!
		@full_width = true
		@samples = repository(:default).adapter.select("SELECT * FROM samples JOIN wells ON wells.sample_id=samples.id JOIN plates ON plates.id=wells.plate_id ORDER BY sample_id LIMIT 20")
		@attrib_keys = JSON.parse(@samples[0].attribs).keys.sort
		slim :"slim/_sample", :layout => :"slim/layout"
	end

	# Plate view entry point: redirect to the first plate
	get '/plate' do
		# Sort by plateID (name) and render the plate view with the first
		@plates = Plate.all(:fields => [:plateID]).map(&:plateID).sort()
		@plate = @plates.first()
		redirect "/plate/#{@plate}"
	end

	# Plate view entry point: loads a particular plate into the plate view
	get '/plate/*' do
		env['warden'].authenticate!
		@plate_names = Plate.all(:fields => [:plateID]).map(&:plateID).sort()
		if @plate_names.include? params[:splat].first
			@plate = Plate.first(:plateID => params[:splat].first)
			@plate_id = @plate.plateID
			# Get a list of batches this plate belongs to
			@batch_names = Batch.all(:pods => {:plate => {:plateID => params[:splat].first}}).map(&:batchID)
			@attribs = Coding.all.map{|x| x.attrib}.uniq.sort()
			slim :"slim/_plate", :layout => :"slim/layout"
		else
			@message = "Plate not found"
			slim :"slim/404", :layout => :"slim/layout"
		end
	end

	get '/destroy/plate/:plate' do
		env['warden'].authenticate!
		return if not env['warden'].user.isAdmin
		Plate.first(:plateID => params[:plate]).destroy!
		redirect "/plate"
	end

	# Batch view entry point: redirect to the first batch
	get '/batch' do
		@batch_names = Batch.all(:order => [:created_at]).map(&:batchID).sort.reverse
		@batch_name = @batch_names.first()
		redirect "/batch/#{@batch_name}"
	end

	# Batch view entry point: loads a particular batch into the batch view
	get '/batch/*' do
		env['warden'].authenticate!
		@batch_names = Batch.all(:order => [:created_at]).map(&:batchID).sort.reverse
		if @batch_names.include? params[:splat].first
			@batch = Batch.first(:batchID => params[:splat].first)
			@batch_id = @batch.id
			@attribs = Coding.all.map{|x| x.attrib}.uniq.sort()
			slim :"slim/_batch", :layout => :"slim/layout"
		else
			if Batch.all.count == 0
				@message = "There are no batches in the system."
			else
				@message = "Batch not found"
			end
			slim :"slim/404", :layout => :"slim/layout"
		end
	end

	get '/add/batch' do
		env['warden'].authenticate!
		@full_width = true
		slim :"slim/_add_batch", :layout => :"slim/layout"
	end

	get '/destroy/batch/:batch' do
		env['warden'].authenticate!
		return if not env['warden'].user.isAdmin
		Batch.first(:batchID => params[:batch]).destroy!
		redirect "/batch"
	end

	post '/add/user' do
		# NOTE: /auth/create is used to create the first admin user to seperate out the code logic from this function

		# Check that the submitting user is valid and an admin
		env['warden'].authenticate!
		return if not env['warden'].user.isAdmin

		# Double check that the user doesn't already exist, otherwise create the user
		if not User.first(:username => params['username']).nil?
			env['warden'].authenticate!
			return "This user already exists exists".to_json
		end
		user = User.new(:username => params['username'], :password => params['password'], :isAdmin=>params['isAdmin']=="on")

		# Save the new user and report any errors or success
		user.save!
		if user.errors.count > 0
			# Really should have been handled on client side, suspecious activity is suspected
			return "Valid input was expected from the submission form. This should never happen.".to_json
		else
			return "OK!".to_json
		end

	end

	get '/modify/users' do
		env['warden'].authenticate!
		return if not env['warden'].user.isAdmin

		@users = User.all
		slim :"slim/_modify_users", :layout => :"slim/layout"
	end

	post '/modify/user' do
		env['warden'].authenticate!
		return if not env['warden'].user.isAdmin

		# Check that the user exists
		user = User.first(:username => params['username'])
		if user.nil?
			return "This user doesn't exist".to_json
		end

		# Some basic checks before deletion
		if params['isAdmin']==false and User.all(:isAdmin => true).count == 1
			return "You must have at least one administrator".to_json
		end

		# Check that the password isn't the dummy password used in the form to edit user passwords
		if params['password'] == "dummy pass"

		end

		# "dummy pass" is the default value on the form. If seen, don't update the password
		begin
			if params['password'] == "dummy pass"
				user.update!(:isAdmin => params['isAdmin']=="on")
			else
				user.update!(:password => params['password'], :isAdmin => params['isAdmin']=="on")
			end
		rescue
			# Really should have been handled on client side, suspecious activity is suspected
			return "Valid input was expected from the submission form. This should never happen.".to_json
		end

		return "OK!".to_json
	end

	post '/destroy/user' do
		env['warden'].authenticate!
		user = User.first(:username => params['username'])

		# Make sure the user the form wasn't messed with
		return if not env['warden'].user.isAdmin
		return if user.nil?

		# Some basic checks before deletion
		if user.isAdmin and User.all(:isAdmin => true).count == 1
			return "You cannot delete all adminstrators".to_json
		end
		if user == env['warden'].user
			return "You cannot delete yourself".to_json
		end

		# If everything is ok, delete the user
		if not user.nil?
			user.destroy!
			return "OK!".to_json
		end
	end


	get '/destroy/database' do
		env['warden'].authenticate!
		return if not env['warden'].user.isAdmin
		reset_database()
		redirect "/start"
	end



	##############################################################################
	#                              Special Routes                                #
	##############################################################################
	# Note: no authentication here
	get '/check_file' do
		type = params[:type]
		#puts "Cecking file /tmp/#{file}"

		###### DB File Check ########
		if params[:type] == "db"
			status = check_db_file(if_:"/tmp/#{session[:db_file]}")
			if status[0] == "Good!"
				session[:attribs] = status[1]
			end
			keystore[session[:db_file]] = status
		end

		###### Coding File Check ########
		if params[:type] == "coding"
			skip = params[:skip]
			skip ||= false

			if skip
				status = ["Good!", nil]
			else
				status = add_coding(if_:"/tmp/#{session[:coding_file]}", attribs:session[:attribs], just_check:true, web_mode:true)
			end
			keystore[session[:coding_file]] = status
		end

		###### Batch File Check ########
		## Handled with the /upload url
		#if params[:type] == "batch"
		#	status = check_batch_file(if_:"/tmp/#{keystore[params[:file]]}")
		#	return {:"error" => "File not formatted correctly"}.to_json
		#end


		return status.to_json
	end

	# Note: no authentication here
	get '/start_db_processing' do
		# Check that both db and coding files successfully verified, then reset the database and process the files.
		# This is done locally with daybreaker to prevent the user from triggering running threads from the web interface
		if keystore[session[:db_file]][0]=="Good!" and keystore[session[:coding_file]][0]=="Good!"
			Thread.start do
				# This should run quickly.
				reset_database()
				# A good status with indicator of nil means the file was skipped, so don't process in this case. This should run quickly.
				add_coding(if_:"/tmp/#{session[:coding_file]}", attribs:session[:attribs], just_check:false, web_mode:true) if not keystore[session[:coding_file]][1].nil?
				# Since the add_data funciton can be long running, a store/key handle is passed to indicate progress back to the web interface
				add_data(if_:"/tmp/#{session[:db_file]}", web_mode:true, store:keystore, key:session[:db_file])
			end
		end
	end

	# Note: no authentication here
	# Should return "Good" and a float complete
	get '/check_db_progress' do
		status = keystore[session[:db_file]]
		status = ["Good!", 0.0] if status.nil?
		return status.to_json
	end


	### Some batch helper functions

	# Should return "Good" and a float complete
	get '/check_batch_progress' do
		status = keystore[:batch_progress]
		status = ["Good!", 0.0] if status.nil?
		return status.to_json
	end

	# Note: no authentication here
	get '/start_batch_processing' do
		# Get the files from the server
		files = params[:batch_files].reject(&:empty?).map {|x| "/tmp/#{keystore[x]}"}
		Thread.start do
			# A good status with indicator of nil means the file was skipped, so don't process in this case. This should run quickly.
			load_batch_files(files, web_mode:true, store:keystore, key:'batch_progress')
		end
	end

	post '/finish' do
		env['warden'].authenticate!
		return if not env['warden'].user.isAdmin
		batch_name = params['batch']
		# Get the batch from the database
		batch = Batch.first(:batchID => batch_name)
		# For each batch mapping
		return if batch.isComplete
		batch.complete!
		redirect "/batch/#{batch_name}"
	end

	#get '/robot-files/remake' do
	#	env['warden'].authenticate!
	#	Thread.new{make_all_robot_files()}
	#	return "OK".to_json
	#end



	##############################################################################
	#                                RESTful API                                 #
	##############################################################################
	# To authenticate all json routes
	before '/json/*' do
		env['warden'].authenticate!
	end

	# Vulnerable to SQL inject, but these are trusted users. Can use the 'sanatize' gem to clean these params
	post '/json/samples' do
		env['warden'].authenticate!
		# Get all needed parameters sent by DataTables
		limit       = params[:length].to_i               || 10
		offset      = params[:start].to_i                || 0
		search_term = params[:search][:value]            || ""
		sort_col    = params[:order]["0"]["column"].to_i || 0
		sort_dir    = params[:order]["0"]["dir"]         || "asc"

		keystore[:samples_cache] = {:sort_col => nil, :sort_dir => nil, :search_term => nil, :samples => nil} if keystore[:samples_cache].nil?
		if keystore[:samples_cache][:sort_col] != sort_col or keystore[:samples_cache][:sort_dir] != sort_dir or keystore[:samples_cache][:search_term] != search_term
			# Build the search clause and query for results
			search_clause = ""
			if not search_term.empty?
				search_clause = "WHERE samples.sample_id LIKE '%#{search_term}%' OR samples.status LIKE '%#{search_term}%' OR samples.volume LIKE '%#{search_term}%' OR samples.attribs LIKE '%#{search_term}%'"
			end
			join_clause = "JOIN wells ON wells.sample_id=samples.id JOIN plates ON plates.id=wells.plate_id"
			query       = "SELECT * FROM samples #{join_clause} #{search_clause} ORDER BY sample_id"
			results     = repository(:default).adapter.select(query)

			# Preallocate for efficiency 
			samples = Array.new(results.length)
			# Keep these column names
			keepem  = [:sample_id, :plate_id, :well] + Sample.first.attribs.keys.sort
			for i in 0..results.length-1
				# Carry over the sample_id... there is some key collision converting from struct to hash
				samp_id = results[i][:sample_id]
				# Get the well location and convert it to a sortable string
				row  = results[i][:row]
				col  = results[i][:col]
				well = col<10 ? "#{row}0#{col}" : "#{row}#{col}"

				# Convert the result to a hash, parse and merge attribs, add sample_id and well
				samp = results[i].to_h
				samp.merge!(JSON.parse(results[i][:attribs]))
				samp[:sample_id] = samp_id
				samp[:well] = well
				# keepem is an array of all attributes we care about, so keepem'! Also convert to an ordered array
				samples[i] = keepem.map{|x| samp.fetch(x)}
			end

			# Do the sorting
			begin
				samples.sort_by!{ |h| h[sort_col] }
			rescue
				# Try sorting as a string
				samples.sort_by!{ |h| h[sort_col].to_s }
			end
			samples.reverse! if sort_dir == "desc"

			# Update cache
			keystore[:samples_cache] = {:sort_col => sort_col, :sort_dir => sort_dir, :search_term => search_term, :samples => samples}
		else
			samples = keystore[:samples_cache][:samples]
		end


		# Return only the requested number of results
		samples_count = samples.count
		samples = samples[offset..limit+offset-1]

		# Convert to json format expected by DataTables and return 
		return {:draw => params[:draw].to_i, :recordsTotal => Sample.count, :recordsFiltered => samples_count, :data => samples}.to_json
	end

	get '/json/sample/:plate/:row/:col' do
		content_type :json
		plate = Plate.first(:plateID => params[:plate])
		well = plate.wells.first(:row => params[:row], :col => params[:col].to_i)
		# Return nothing if the well is invalid (doesn't exist)
		return [].to_json if well.nil?
		# Get the well's sample
		sample = well.sample
		# A batch mapping may place a sample in this well that is still empty
		# because the batch is not complete. These are 'pending' samples or
		# ones that are not realized yet.
		realized = true
		# If there is no current sample find it from a potential provider

		if sample.nil?
			# see if a mapping will eventually provide one
			provider = Mapping.all(:destination => well).provider
			# If more than one provider is found this is bad because mappings should be one-to-one
			if provider.count != 1
				puts "There is more than one mapping to this well. This shouldn't happen" if provider.count >1
				return [].to_json
			else
				# Otherwise, use the first (only) provider well's sample as this well's sample
				sample = provider.first.sample
				# Set realized to false, so the interface knows that this mapping hasn't happend yet (hasn't been realized)
				realized = false
			end
		end

		# Get the mapping information
		provider    = Mapping.all(:destination => well).provider.first || well
		destination = Mapping.all(:provider => well).destination.first || well
		from        = "#{provider.plate.name} #{provider.long}"
		to          = "#{destination.plate.name} #{destination.long}"
		to          = "(Not Mapped)" if destination==provider

		# If the sample exists, just return it (set realized to true so interface knows this sample is really there and not just a mapping)
		return sample.attributes.merge({well: well.short, realized: realized, from:from, to:to}).to_json
	end


	post '/json/attributes/plates' do
		plates   = params['plates']
		attrib   = params['attrib']
		values   = nil
		provided = nil

		# The status attribute we want is actually found in the well object
		if attrib == "status"
			# Get all unique native well statuses or those provided by other wells
			values   = Plate.all(:plateID => plates).wells.map{|x| x.status}.uniq
		# Otherwise get the attribute from the sample
		else
			plates        = Plate.all(:plateID => plates).map{|x| x.id}
			dest_wells    = repository(:default).adapter.select("SELECT id FROM wells WHERE plate_id IN(#{plates.join(',')}) ORDER BY id")
			prov_wells    = repository(:default).adapter.select("SELECT provider_id FROM mappings WHERE destination_id IN(#{dest_wells.join(',')}) ORDER BY provider_id")
			wells         = (prov_wells + dest_wells).compact.uniq

			samples       = repository(:default).adapter.select("SELECT sample_id FROM wells WHERE id IN(#{wells.join(',')}) ORDER BY id")
			samples       = samples.compact.uniq

			attribs       = repository(:default).adapter.select("SELECT attribs FROM samples WHERE id IN(#{samples.join(',')}) ORDER BY id")
			values        = attribs.map{|x| JSON.parse(x)[attrib]}.uniq

			# Way slower...
			#values   = Plate.all(:plateID => plates).wells.map{|x| x.sample or (x.provider and x.provider.sample) if not x.nil?}.uniq
			##provided = Mapping.all(:destination => Plate.all(:plateID => plates).wells).destionation
			##values   = Plate.all(:plateID => plates).wells.map{|x| x.sample or x.provider.sample}.uniq
		end

		# Sort unless true/false values (unsortable)
		begin
			values.compact!
			values.sort!
		rescue ArgumentError
			nil
		end

		return values.to_json
	end


	get '/json/plate/:plate' do
		content_type :json
		plate = Plate.first(:plateID => params[:plate])
		response = {}

		# This could be rewritten to be much faster, as in
		# For each well on the plate
		plate.wells.each do |well|
			# Set the realization to true by default
			realized = true

			# If there is no sample in this well
			if well.sample.nil?
				# try to find a mapping that provides one (and mark as unrealized)
				provider = well.provider
				if not provider.nil?
					# Otherwise get the providing well's sample, status, and if it is a control
					well.sample = provider.sample
					# This isn't realized yet, so set the flag to false
					realized = false
				end
			end

			# Check to see if this well is mapped as a provider
			if not well.destination.nil?
				realized = false if not Mapping.first(:provider => well).isComplete
			end

			response[well.short] = { well: well.attributes.merge({realized: realized}), sample: well.sample }
		end
		response.merge(plate.attributes)
		return response.to_json
	end





	##############################################################################
	#                               File Handlers                                #
	##############################################################################
	### File Uploaders ###
	# Handle POST-request (Receive and save the uploaded file)
	# Note: No authentication is used here (needed for dbfile uploads)
	post '/upload/:type' do
		file = "#{params[:type]}_upload_" + SecureRandom.hex
		File.open('/tmp/' + file, "w") do |f|
			f.write(params['file'][:tempfile].read)
		end
		puts "Wrote file to /tmp/#{file}"

		# For everthing but batch files,
		# use [file type]_file as a session variable and give it back to the browser
		if not params[:type] == 'batch'
			session[:"#{params[:type]}_file"] = file
		# Otherwise, for batches, validate the file
		#  if it passes, store the filename => local_file key/val locally for later (processing).
		else
			status = check_batch_file(if_:"/tmp/#{file}")
			# If the file fails validation, return the error code.
			if status[0] == "Error"
				halt 423, status[1].to_json
			else
				keystore[params[:file][:filename]] = file
				return status.to_json
			end
		end
		#response.set_cookie(:file, {:value=> db_file, :max_age => "2592000"})
		erb "File uploaded; cookie set"
	end

	### File Downloaders ###
	post '/robot_file' do
		batch = params['batch']
		debug = params['debug']=="true"

		# Make sure parameters are valid
		return if Batch.first(:batchID => batch).nil?

		# Otherwise generate a robot file and send it
		create_robot_file(batch, debug:debug)
		robofile = File.join(File.dirname(__FILE__),'db/robot_files', params[:batch]+".csv")

		if File.exist?(robofile)
			send_file(robofile, :type => 'application/zip', :disposition => 'attachment', :filename => File.basename(robofile))
		else
			@message = "There was an error on the server side creating the requested robot file."
			slim :"slim/404"
		end
	end
	#
	#get '/robot-files/zip' do
	#	zipfile_name = File.join(File.dirname(__FILE__),"db","robot_files","robot_files.zip")
	#	if File.exist?(zipfile_name)
	#		send_file(zipfile_name,:disposition => 'attachment',:filename => File.basename(zipfile_name))
	#	else
	#		@message = "Robot file not found"
	#		slim :"slim/404"
	#	end
	#end
	#
	get '/titan_file/*' do
		create_gene_titan_file(params[:splat].first)
		titanfile = File.join(File.dirname(__FILE__),"db","gene_titan_files", params[:splat].first+".xls")
		if File.exist?(titanfile)
			send_file(titanfile,:disposition => 'attachment',:filename => File.basename(titanfile))
		else
			@message = "Gene titan file not found"
			slim :"slim/404"
		end
	end

	##############################################################################
	#                                 User Auth                                  #
	##############################################################################
	get '/auth/login' do
		@message ||= "Samasy Login"
		slim :'slim/_login'
	end

	post '/auth/login/verify' do
		env['warden'].authenticate!
		if session[:return_to].nil? or session[:return_to] == '/auth/login'
			redirect '/'
		else
			redirect session[:return_to]
		end
	end

	# This is used only to create the first admin user
	post '/auth/create' do
		# Get the auto admin key if it exists
		key = session[:auto_admin]
		if keystore[key] == "valid"
			user = User.create!(:username => params['username'], :password => params['password'], :isAdmin=>true)
			# Remove the auto admin key
			keystore.delete! key
			session.delete :auto_admin
		end

		env['warden'].authenticate!
		return "OK!".to_json
	end

	get '/auth/user/availability/?:negate?' do
		response = true
		if not User.first(:username => params['username']).nil?
			response = false
		end
		if params[:negate]=="negate"
			response = !response
		end
		return {valid:response}.to_json
	end

	get '/auth/logout' do
		env['warden'].logout
		session.delete :message
		@message ||= "You've been logged out"
		slim :'slim/_login'
	end

	post '/auth/unauthenticated' do
		session[:return_to] = env['warden.options'][:attempted_path] if session[:return_to].nil?
		redirect 'auth/login'
	end

end
