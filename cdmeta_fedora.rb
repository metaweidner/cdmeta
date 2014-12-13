require 'open-uri'
require 'fileutils'
require 'json'
require 'nokogiri'
require 'yaml'
require 'colorize'
require './cdmeta_methods'

admin_config = YAML::load_file(File.join(__dir__, 'config.yml'))
fedora_config = YAML::load_file(File.join(__dir__, 'config_fedora.yml'))

server = admin_config['cdm']['server']
port = admin_config['cdm']['port']
cdm_url = "http://#{server}:#{port}/dmwebservices/index.php?q="

collections_config = admin_config['collections']
collection_titles = collections_to_hash(collections_config)

meta_map_config = fedora_config['meta_map']
meta_map = meta_map_to_hash(meta_map_config)

total_collections = 0
total_objects = 0
total_files = 0

puts "\n------------------------------------------------"
puts "Downloading UH Digital Library Metadata & Files:"

### EITHER uncomment next two lines for all collections
# collections = get_collections(cdm_url)
# collection_aliases = get_collection_aliases(collections)
### OR use array of aliases

collection_aliases = ["p15195coll11", "p15195coll39"]
### test collections
# p15195coll39 (theodor de bry)
# p15195coll11 (scenes middle east)
# earlytex (early texas documents)
# jmac (jagdish mehra audio)
# saeng (houston saengerbund records)

# output collection names to the console
collection_aliases.each do |collection_alias|
	collection_title = collection_titles.fetch(collection_alias)
	puts "  - #{collection_title} (#{collection_alias})".red
end
puts "------------------------------------------------\n"

# loop through collections
collection_aliases.each do |collection_alias|

	# get the field information and map to dc
	field_info = get_field_info(cdm_url, collection_alias)
	labels_and_nicks = get_labels_and_nicks(field_info)
	collection_map = get_collection_map(labels_and_nicks, meta_map)

	# create directory for collection download
	collection_title = collection_titles.fetch(collection_alias)
	collection_download_dir = "#{admin_config['cdm']['download_dir']}/#{collection_title}_(#{collection_alias})"
	FileUtils::mkdir_p collection_download_dir
	puts "\nDownloading Collection: "
	puts collection_download_dir.red + "\n\n"

	# get all objects in collection and loop through each one
	object_count = 0
	objects = get_items(cdm_url, collection_alias)
	objects['records'].each do |record|

		object_count += 1
		object_download_dir = File.join(collection_download_dir, "#{collection_alias}_#{record['pointer']}")
		FileUtils::mkdir_p object_download_dir

		# get the object metadata
		object_pid = "#{collection_alias}:#{record['pointer']}"
		object_info = get_item_info(cdm_url, collection_alias, record['pointer'])
		object_name = object_info.fetch("title")
		object_dc = get_item_dc_fedora(object_info, collection_map)
		object_tech = get_item_tech_fedora(object_info, collection_map)

		# get the object foxml
		object_foxml = get_foxml(object_pid, object_name, object_dc, object_tech, collection_alias, collection_title)

		if record['filetype'] == "cpd" # compound object

			puts "Downloading Compound Object: #{record['pointer']}"

			# get the items in the object and loop through each one
			file_count = 0
			compound_object_info = get_compound_object_info(cdm_url, collection_alias, record['pointer'])
			compound_object_items = get_compound_object_items(compound_object_info)
			compound_object_items.each do |pointer|

				file_count += 1
				puts "... getting item #{pointer}"

				# get the item metadata
				item_pid = "#{collection_alias}:#{pointer}"
				item_info = get_item_info(cdm_url, collection_alias, pointer)
				item_name = item_info.fetch("title").gsub('&', '&amp;')
				item_dc = get_item_dc_fedora(item_info, collection_map)
				item_tech = get_item_tech_fedora(item_info, collection_map)

				# get the item foxml
				item_foxml = get_foxml(item_pid, item_name, item_dc, item_tech, collection_alias, collection_title, object_pid, object_name)

				# write the item foxml file
				File.open(File.join(object_download_dir, "#{collection_alias}_#{record['pointer']}_#{pointer}.xml"), 'w') {|f| f.write(item_foxml.to_xml) }

			end

			puts "Compound Object Downloaded: " + record['pointer'].to_s.green + " (#{file_count} files)" + "\n\n"
			total_files += file_count

		else
			# write the object foxml file
			File.open(File.join(object_download_dir, "#{collection_alias}_#{record['pointer']}.xml"), 'w') {|f| f.write(object_foxml.to_xml.gsub(':FORMAT>', ':format>')) }

			puts "Single Object Downloaded: " + record['pointer'].to_s.green + "\n\n"
			total_files += 1
		end
	end

	puts "-----------------------------"
	puts "Collection Download Complete: " + "#{collection_title} (#{object_count})".green
	puts "-----------------------------\n"
	total_collections += 1
	total_objects += object_count

end

puts "\nUHDL Download Complete".green
puts "Total Collections: #{total_collections}"
puts "Total Objects: #{total_objects}"
puts "Total Files: #{total_files}\n\n"
