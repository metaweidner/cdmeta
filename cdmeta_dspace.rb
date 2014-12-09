### cdmeta_dspace.rb (ajweidner@uh.edu)
### export contentdm metadata and files
### in dspace simple archive format

require 'open-uri'
require 'fileutils'
require 'json'
require 'nokogiri'
require 'yaml'
require 'colorize'
require './cdmeta_methods'

# load yaml config files
admin_config = YAML::load_file(File.join(__dir__, 'config.yml'))
dspace_config = YAML::load_file(File.join(__dir__, 'config_dspace.yml'))

# set up cdm api urls
server = admin_config['cdm']['server']
port = admin_config['cdm']['port']
cdm_url = "http://#{server}:#{port}/dmwebservices/index.php?q="
cdm_get_file_url = "http://#{server}/contentdm/file/get/"

# get metadata map and collection titles
meta_map_config = dspace_config['meta_map']
meta_map = meta_map_to_hash_dspace(meta_map_config)
collections_config = admin_config['collections']
collection_titles = collections_to_hash(collections_config)

puts "\n------------------------------------------------"
puts "Downloading UH Digital Library Metadata & Files:"
collection_count = 0
total_object_count = 0
download_start = Time.now

### uncomment next two lines for all collections
# collections = get_collections(cdm_url)
# collection_aliases = get_collection_aliases(collections)

### use array for limited number of collections
collection_aliases = ["p15195coll11", "p15195coll39"]

### dams test collections ###
# p15195coll39 theodor de bry
# p15195coll11 scenes middle east
# earlytex early texas documents
# jmac jagdish mehra audio
# saeng houston saengerbund records

# output collection names to the console
collection_aliases.each do |collection_alias|
	collection_title = collection_titles.fetch(collection_alias)
	puts "  - #{collection_title} (#{collection_alias})".red
end

puts "------------------------------------------------\n"

# loop through collections
collection_aliases.each do |collection_alias|

	collection_start = Time.now

	# get the field information and map to dspace dc
	field_info = get_field_info(cdm_url, collection_alias)
	labels_and_nicks = get_labels_and_nicks(field_info)
	collection_map = get_collection_map(labels_and_nicks, meta_map)

	# create archive directory for download
	collection_title = collection_titles.fetch(collection_alias)
	download_dir = "#{admin_config['cdm']['download_dir']}/#{collection_title}_(#{collection_alias})"
	FileUtils::mkdir_p download_dir
	puts "\nDownloading Collection:\n" + "#{download_dir}".red + "\n"
	object_count = 0

	# get all objects in collection and loop through each one
	items = get_items(cdm_url, collection_alias)
	items['records'].each do |record|

		object_start = Time.now

		# create object directory and prepare metadata variables
		object_count += 1
		object_download_dir = "#{download_dir}/item_%04d" % object_count
		FileUtils::mkdir_p object_download_dir
		content_file = ""
		metadata_file = "<dublin_core>\n"
		page_num = 0

		if record['filetype'] == "cpd" # download compound object

			puts "\nDownloading Compound Object: #{record['pointer']} (item_%04d)" % object_count

			# get the object metadata
			object_info = get_item_info(cdm_url, collection_alias, record['pointer'])
			new_object_info = transform_item_dspace(object_info, collection_map)

			# store the object metadata
			new_object_info.each {|line| metadata_file += "\t#{line}\n"}

			# get the items in the object and loop through each one
			compound_object_info = get_compound_object_info(cdm_url, collection_alias, record['pointer'])
			compound_object_items = get_compound_object_items(compound_object_info)
			table_of_contents = ""

			compound_object_items.each do |pointer|

				puts "... getting file info #{pointer}"
				# item_start = Time.now
				page_num += 1

				# get the item metadata
				item_info = get_item_info(cdm_url, collection_alias, pointer)
				new_item_info = transform_item_dspace(item_info, collection_map)

				# get new file name and store in content file
				new_file_name = construct_new_file_name(item_info, page_num)
				content_file += new_file_name + "\n"

				# store item descriptions, captions, and inscriptions in object metadata
				new_item_info.each do |line|
					if line.include? "element=\"description"
						original_description = line.split(">")
						new_description = "#{original_description[0]}>(File #{new_file_name}) #{original_description[1]}>"
						metadata_file += "\t#{new_description}\n"
					else
						next
					end
				end

				# store the item title in the table of contents
				table_of_contents += "File #{new_file_name}: " + item_info.fetch("title") + "\n" unless item_info.fetch("title").nil?

				# download file from contentdm
				puts "... downloading file \'#{new_file_name}\' "
				# print "... downloading file \'#{new_file_name}\' "
				download_file_dspace(object_download_dir, new_file_name, cdm_get_file_url, collection_alias, pointer)
				# item_finish = Time.now
				# item_time = Time.at(item_finish - item_start).utc.strftime("%M:%S")
				# puts "#{item_time}"

			end

			# store table of contents in metadata
			metadata_file += "\t<dcvalue element=\"description\" qualifier=\"tableofcontents\">#{table_of_contents.chomp}</dcvalue>\n"

		else # download single object

			puts "\nDownloading Single Object: #{record['pointer']} (item_%04d)\n" % object_count
			page_num += 1

			# get the item information
			item_info = get_item_info(cdm_url, collection_alias, record['pointer'])
			new_item_info = transform_item_dspace(item_info, collection_map)

			# store the item metadata
			new_item_info.each {|line| metadata_file += "\t#{line}\n"}

			# store file name in content file
			new_file_name = construct_new_file_name(item_info, page_num)
			content_file += new_file_name + "\n"

			# download file from contentdm
			puts "... downloading file \'#{new_file_name}\'"
			download_file_dspace(object_download_dir, new_file_name, cdm_get_file_url, collection_alias, record['pointer'])

		end

		# write the metadata and content files
		metadata_file += "</dublin_core>"
		File.open(object_download_dir + "/contents", 'w') {|f| f.write(content_file.chomp) }
		File.open(object_download_dir + "/dublin_core.xml", 'w') {|f| f.write(metadata_file) }

		# output object download info to the console
		object_finish = Time.now
		object_time = Time.at(object_finish - object_start).utc.strftime("%M:%S")
		page_num > 1 ? word = "Files" : word = "File"
		puts "Object #{record['pointer']} with #{page_num} #{word} downloaded in #{object_time}".green + "\n"

	end

	# output collection download info to the console
	collection_finish = Time.now
	collection_time = Time.at(collection_finish - collection_start).utc.strftime("%H:%M:%S")
	puts "\nCollection Download Complete: " + "#{collection_title} (#{object_count} objects in #{collection_time})".green + "\n"
	collection_count += 1
	total_object_count += object_count

end

# output repository download info to the console
download_finish = Time.now
download_time = Time.at(download_finish - download_start).utc.strftime("%H:%M:%S")

puts "\n\n----------------------"
puts "UHDL Download Complete".green
puts "Total Collections: #{collection_count}"
puts "Total Objects: #{total_object_count}"
puts "Total Time: #{download_time}"
puts "----------------------\n\n"
