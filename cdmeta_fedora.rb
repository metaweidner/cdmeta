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

meta_map_config = fedora_config['meta_map']
meta_map = meta_map_to_hash(meta_map_config)
collections_config = admin_config['collections']
collection_titles = collections_to_hash(collections_config)

puts "\n------------------------------------------------"
puts "Downloading UH Digital Library Metadata & Files:"
collection_count = 0
total_object_count = 0

### EITHER uncomment next two lines for all collections
# collections = get_collections(cdm_url)
# collection_aliases = get_collection_aliases(collections)

### OR use array of aliases
# p15195coll39 (theodor de bry)
# p15195coll11 (scenes middle east)
# earlytex (early texas documents)
# jmac (jagdish mehra audio)
# saeng (houston saengerbund records)
collection_aliases = ["djscrew"]

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

	# create archive directory for download
	collection_title = collection_titles.fetch(collection_alias)
	download_dir = "#{admin_config['cdm']['download_dir']}/#{collection_title}_(#{collection_alias})"
	FileUtils::mkdir_p download_dir
	puts "\nDownloading Collection: "
	puts download_dir.red + "\n\n"
	object_count = 0

	# get all objects in collection and loop through each one
	items = get_items(cdm_url, collection_alias)
	items['records'].each do |record|

		object_count += 1
		object_pid = "#{collection_alias}:#{record['pointer']}"

		if record['filetype'] == "cpd" # download compound object

			puts "Downloading Compound Object: #{record['pointer']}"

			# get the object metadata
			object_info = get_item_info(cdm_url, collection_alias, record['pointer'])
			new_object_info = transform_item_fedora(object_info, collection_map)
			object_name = object_info.fetch("title").gsub('&', '&amp;')

			# store the dc metadata
			dc_datastream = "\t"*4 + "<oai_dc:dc xmlns:oai_dc=\"http://www.openarchives.org/OAI/2.0/oai_dc/\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:dcterms=\"http://purl.org/dc/terms/\">\n"
			new_object_info.each {|line| dc_datastream << "\t"*5 + "#{line}\n"}
			dc_datastream << "\t"*4 + "</oai_dc:dc>\n"

			# get the foxml file
			foxml_file = get_fedora_foxml(object_name, object_pid, dc_datastream, collection_alias)

			# write the foxml file
			File.open(File.join(download_dir, "#{collection_alias}_#{record['pointer']}.xml"), 'w') {|f| f.write(foxml_file) }

			# get the items in the object and loop through each one
			compound_object_info = get_compound_object_info(cdm_url, collection_alias, record['pointer'])
			compound_object_items = get_compound_object_items(compound_object_info)
			table_of_contents = ""
			page_num = 0
			compound_object_items.each do |pointer|
				page_num += 1
				item_pid = "#{collection_alias}:#{pointer}"
				puts "... getting item #{pointer}"

				# get the item metadata
				item_info = get_item_info(cdm_url, collection_alias, pointer)
				new_item_info = transform_item_fedora(item_info, collection_map)
				item_name = item_info.fetch("title").gsub('&', '&amp;')

				# store the dc metadata
				dc_datastream = "\t"*4 + "<oai_dc:dc xmlns:oai_dc=\"http://www.openarchives.org/OAI/2.0/oai_dc/\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:dcterms=\"http://purl.org/dc/terms/\">\n"
				new_item_info.each {|line| dc_datastream << "\t"*5 + "#{line}\n"}
				dc_datastream << "\t"*4 + "</oai_dc:dc>\n"

				# get the foxml file
				foxml_file = get_fedora_foxml(item_name, item_pid, dc_datastream, collection_alias, object_pid)

				# write the foxml file
				File.open(File.join(download_dir, "#{collection_alias}_#{record['pointer']}_#{pointer}.xml"), 'w') {|f| f.write(foxml_file) }
			end

			puts "Compound Object Downloaded: " + "#{record['pointer']} (#{page_num} files)".green + "\n\n"

		else # download single object

			# get the object metadata
			object_info = get_item_info(cdm_url, collection_alias, record['pointer'])
			new_object_info = transform_item_fedora(object_info, collection_map)
			object_name = object_info.fetch("title").gsub('&', '&amp;')

			# store the dc metadata
			dc_datastream = "\t"*4 + "<oai_dc:dc xmlns:oai_dc=\"http://www.openarchives.org/OAI/2.0/oai_dc/\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:dcterms=\"http://purl.org/dc/terms/\">\n"
			new_object_info.each {|line| dc_datastream << "\t"*5 + "#{line}\n"}
			dc_datastream << "\t"*4 + "</oai_dc:dc>\n"

			# get the foxml file
			foxml_file = get_fedora_foxml(object_name, object_pid, dc_datastream, collection_alias)

			# write the foxml file
			File.open(File.join(download_dir, "#{collection_alias}_#{record['pointer']}.xml"), 'w') {|f| f.write(foxml_file) }
			puts "Single Object Downloaded: " + record['pointer'].to_s.green + "\n\n"
		end
	end

	puts "-----------------------------"
	puts "Collection Download Complete: " + "#{collection_title} (#{object_count})".green
	puts "-----------------------------\n"
	collection_count += 1
	total_object_count += object_count

end

puts "\nUHDL Download Complete".green
puts "Total Collections: #{collection_count}"
puts "Total Objects: #{total_object_count}\n\n"
