
def get_collections(cdm_url)
	cdm_collections_url = cdm_url + "dmGetCollectionList/json"
	collections = JSON.parse(open(cdm_collections_url).read)
end


def get_collection_aliases(collections)
	collection_aliases = []
	collections.each {|v| collection_aliases << v['secondary_alias']}
	collection_aliases
end


def get_field_info(cdm_url, collection_alias)
	cdm_field_info_url = cdm_url + "dmGetCollectionFieldInfo/#{collection_alias}/json"
	field_info = JSON.parse(open(cdm_field_info_url).read)
end


def get_labels_and_nicks(field_info)
	labels_and_nicks = {}
	field_info.each {|field| labels_and_nicks.store(field['name'], field['nick'])}
	labels_and_nicks
end


def meta_map_to_hash(meta_map_config)
	meta_map_hash = {}
	meta_map_config.each {|field| meta_map_hash.store(field['label'], {"label" => field['label'], "namespace" => field['namespace'], "map" => field['map'], "type" => field['type'], "vocab" => field['vocab']}) }
	meta_map_hash
end


def meta_map_to_hash_dspace(meta_map_config)
	meta_map_hash = {}
	meta_map_config.each {|field| meta_map_hash.store(field['label'], {"label" => field['label'], "namespace" => field['namespace'], "element" => field['element'], "qualifier" => field['qualifier'], "vocab" => field['vocab']}) }
	meta_map_hash
end


def collections_to_hash(collections_config)
	collections_hash = {}
	collections_config.each {|collection| collections_hash.store(collection['alias'], collection['title']) }
	collections_hash
end


def collection_titles_to_hash(collections_config)
	collections_hash = {}
	collections_config.each {|collection| collections_hash.store(collection['alias'], collection['title']) }
	collections_hash
end


def collection_long_titles_to_hash(collections_config)
	collections_hash = {}
	collections_config.each {|collection| collections_hash.store(collection['alias'], collection['long_title']) }
	collections_hash
end


def get_collection_map(labels_and_nicks, meta_map)
	collection_map = {}
	field_map = {}
	labels_and_nicks.each do |label, nick|
		field_map = meta_map.fetch(label)
		collection_map.store(nick, field_map)
	end
	# contentdm metadata fields
	collection_map.store("dmaccess", {"label" => "dmaccess", "namespace" => "cdm", "map" => "dmAccess", "type" => nil, "vocab" => nil})
	collection_map.store("dmimage", {"label" => "dmimage", "namespace" => "cdm", "map" => "dmImage", "type" => nil, "vocab" => nil})
	collection_map.store("restrictionCode", {"label" => "restrictionCode", "namespace" => "cdm", "map" => "restrictionCode", "type" => nil, "vocab" => nil})
	collection_map.store("cdmfilesize", {"label" => "cdmfilesize", "namespace" => "cdm", "map" => "fileSize", "type" => nil, "vocab" => nil})
	collection_map.store("cdmfilesizeformatted", {"label" => "cdmfilesizeformatted", "namespace" => "cdm", "map" => "fileSizeFormatted", "type" => nil, "vocab" => nil})
	collection_map.store("cdmprintpdf", {"label" => "cdmprintpdf", "namespace" => "cdm", "map" => "printPDF", "type" => nil, "vocab" => nil})
	collection_map.store("cdmhasocr", {"label" => "cdmhasocr", "namespace" => "cdm", "map" => "hasOCR", "type" => nil, "vocab" => nil})
	collection_map.store("cdmisnewspaper", {"label" => "cdmisnewspaper", "namespace" => "cdm", "map" => "isNewspaper", "type" => nil, "vocab" => nil})
	collection_map
end


def get_items(cdm_url, collection_alias)
	cdm_items_url = cdm_url + "dmQuery/#{collection_alias}/0/title/title/2000/1/0/0/0/0/0/0/json"
	items = JSON.parse(open(cdm_items_url).read)
end


def get_item_info(cdm_url, collection_alias, item_pointer)
	cdm_item_info_url = cdm_url + "dmGetItemInfo/#{collection_alias}/#{item_pointer}/json"
	item_info = JSON.parse(open(cdm_item_info_url).read)
end


def get_item_dc_fedora(item_info, collection_map)
	item_dc = []
	field_info = {}
	item_info.each do |nick, value|
		if value.class == Hash # blank fields return an empty hash
			next
		else
			field_info = collection_map.fetch(nick)
			namespace = field_info['namespace']

			if (namespace == "dc") || (namespace == "dcterms")

				map = field_info['map']
				label = field_info['label']
				type = field_info['type']
				value = value.strip.chomp(";") # remove white space, trailing semicolon

				# parse multi-value fields; exclude: title, transcript, description, inscription, caption
				if (value.include? ";") && (map != ("title"||"transcript")) \
					&& (label != "Description") \
					&& (type != ("inscription"||"caption"))

					values = value.split(";")
					values.each {|v| item_dc << [namespace, map, v.strip] }

				else # single value fields

					item_dc << [namespace, map, value]

				end
			end
		end
	end
	item_dc
end


def get_item_tech_fedora(item_info, collection_map)
	item_tech = []
	field_info = {}
	item_info.each do |nick, value|
		if value.class == Hash # blank fields return an empty hash
			next
		else
			field_info = collection_map.fetch(nick)
			namespace = field_info['namespace']

			if (namespace == "uhlibadmin")

				map = field_info['map']
				value = value.strip.chomp(";") # remove white space, trailing semicolon
				item_tech << [namespace, map, value]

			end
		end
	end
	item_tech
end


def get_item_foxml(pid, name, dcmeta, techmeta, collection_alias, compound_object_pid = nil, compound_object_name = nil)

	foxml = Nokogiri::XML::Builder.new(:encoding => 'UTF-8') do |xml|

		xml['foxml'].digitalObject(:VERSION => 1.1, :PID => "#{pid}", 'xmlns:foxml' => 'info:fedora/fedora-system:def/foxml#', 'xmlns:xsi' => 'http://www.w3.org/2001/XMLSchema-instance', 'xsi:schemaLocation' => 'info:fedora/fedora-system:def/foxml# http://www.fedora.info/definitions/1/0/foxml1-1.xsd') {
			xml['foxml'].objectProperties {
				xml['foxml'].property(:NAME => 'info:fedora/fedora-system:def/model#state', :VALUE => 'A')
				xml['foxml'].property(:NAME => 'info:fedora/fedora-system:def/model#label', :VALUE => "#{name}")
			}
			# dublin core datastream
			xml['foxml'].datastream(:ID => 'DC', :STATE => 'A', :CONTROL_GROUP => 'X', :VERSIONABLE => 'true') {
				xml['foxml'].datastreamVersion( :ID => 'DC1.0', :MIMETYPE => 'text/xml', :FORMAT_URI => 'http://www.openarchives.org/OAI/2.0/oai_dc/', :LABEL => 'Dublin Core Record for this object') {
					xml['foxml'].xmlContent {
						xml['oai_dc'].dc('xmlns:oai_dc' => 'http://www.openarchives.org/OAI/2.0/oai_dc/', 'xmlns:dc' => 'http://purl.org/dc/elements/1.1/', 'xmlns:dcterms' => 'http://purl.org/dc/terms/') {
							dcmeta.each {|node| xml[node[0]].send(node[1], node[2]) } # <ns:map>value</ns:map>
						}
					}
				}
			}
			# rels-ext datastream
			xml['foxml'].datastream(:ID => 'RELS-EXT', :STATE => 'A', :CONTROL_GROUP => 'X', :VERSIONABLE => 'true') {
				xml['foxml'].datastreamVersion(:ID => 'RELS-EXT1.0', :MIMETYPE => 'application/rdf+xml', :FORMAT_URI => 'info:fedora/fedora-system:FedoraRELSExt-1.0', :LABEL => 'RDF Statements about this object') {
					xml['foxml'].xmlContent {
						xml['rdf'].RDF('xmlns:rdf' => 'http://www.w3.org/1999/02/22-rdf-syntax-ns#', 'xmlns:rdfs' => 'http://www.w3.org/2000/01/rdf-schema#', 'xmlns:fedora' => 'info:fedora/fedora-system:def/relations-external#', 'xmlns:myns' => 'http://www.nsdl.org/ontologies/relationships#', 'xmlns:dc' => 'http://purl.org/dc/elements/1.1/', 'xmlns:dcterms' => 'http://purl.org/dc/terms/', 'xmlns:oai_dc' => 'http://www.openarchives.org/OAI/2.0/oai_dc/') {
							xml['rdf'].Description('rdf:about' => "info:fedora/#{pid}") {
								xml['fedora'].isMemberOfCollection('rdf:resource' => "info:fedora/uhdamstf:#{collection_alias}")
								xml['myns'].isPartOf('rdf:resource' => "info:fedora/#{compound_object_pid}") if compound_object_pid
							}
						}
					}
				}
			}
			# technical metadata datastream
			xml['foxml'].datastream(:ID => 'UHLIBTECH', :STATE => 'A', :CONTROL_GROUP => 'X', :VERSIONABLE => 'true') {
				xml['foxml'].datastreamVersion(:ID => 'UHLIBTECH1.0', :MIMETYPE => 'text/xml', :FORMAT_URI => 'info:fedora/format:xml:uhlibadmin', :LABEL => 'UH Libraries Technical Metadata Record') {
					xml['foxml'].xmlContent {
						xml['uhlibadmin'].admin('xmlns:uhlibadmin' => 'http://digital.lib.uh.edu/uhlibadmin:tech') {
							xml['uhlibadmin'].technical {
								techmeta.each {|node| xml[node[0]].send(node[1], node[2]) } # <ns:map>value</ns:map>
							}
						}
					}
				}
			}
		}
	end
	foxml
end


def get_collection_foxml(collection_alias, collection_long_title)

	foxml = Nokogiri::XML::Builder.new(:encoding => 'UTF-8') do |xml|

		xml['foxml'].digitalObject( :VERSION => 1.1, :PID => "uhdamstf:#{collection_alias}", 'xmlns:foxml' => 'info:fedora/fedora-system:def/foxml#', 'xmlns:xsi' => 'http://www.w3.org/2001/XMLSchema-instance', 'xsi:schemaLocation' => 'info:fedora/fedora-system:def/foxml# http://www.fedora.info/definitions/1/0/foxml1-1.xsd') {
			xml['foxml'].objectProperties {
				xml['foxml'].property(:NAME => 'info:fedora/fedora-system:def/model#state', :VALUE => 'A')
				xml['foxml'].property(:NAME => 'info:fedora/fedora-system:def/model#label', :VALUE => "Service Definition Object (Collection) for #{collection_long_title}")
			}
			# dublin core datastream
			xml['foxml'].datastream(:ID => 'DC', :STATE => 'A', :CONTROL_GROUP => 'X', :VERSIONABLE => 'true') {
				xml['foxml'].datastreamVersion( :ID => 'DC1.0', :MIMETYPE => 'text/xml', :FORMAT_URI => 'http://www.openarchives.org/OAI/2.0/oai_dc/', :LABEL => 'Dublin Core Record for this object') {
					xml['foxml'].xmlContent {
						xml['oai_dc'].dc('xmlns:oai_dc' => 'http://www.openarchives.org/OAI/2.0/oai_dc/', 'xmlns:dc' => 'http://purl.org/dc/elements/1.1/') {
							xml['dc'].title "Service Definition Object for #{collection_long_title}"
							xml['dc'].identifier "uhdamstf:#{collection_alias}"
						}
					}
				}
			}
			# rels-ext datastream
			xml['foxml'].datastream(:ID => 'RELS-EXT', :STATE => 'A', :CONTROL_GROUP => 'X', :VERSIONABLE => 'true') {
				xml['foxml'].datastreamVersion(:ID => 'RELS-EXT1.0', :MIMETYPE => 'application/rdf+xml', :FORMAT_URI => 'info:fedora/fedora-system:FedoraRELSExt-1.0', :LABEL => 'RDF Statements about this object') {
					xml['foxml'].xmlContent {
						xml['rdf'].RDF('xmlns:rdf' => 'http://www.w3.org/1999/02/22-rdf-syntax-ns#', 'xmlns:rdfs' => 'http://www.w3.org/2000/01/rdf-schema#', 'xmlns:fedora' => 'info:fedora/fedora-system:def/relations-external#', 'xmlns:myns' => 'http://www.nsdl.org/ontologies/relationships#', 'xmlns:dc' => 'http://purl.org/dc/elements/1.1/', 'xmlns:dcterms' => 'http://purl.org/dc/terms/', 'xmlns:oai_dc' => 'http://www.openarchives.org/OAI/2.0/oai_dc/') {
							xml['rdf'].Description('rdf:about' => "info:fedora/uhdamstf:#{collection_alias}") {
								xml['fedora'].hasModel('rdf:resource' => 'info:fedora/fedora-system:ServiceDefinition-3.0')
							}
						}
					}
				}
			}
			# method map datastream
			xml['foxml'].datastream(:ID => 'METHODMAP', :STATE => 'A', :CONTROL_GROUP => 'X', :VERSIONABLE => 'true') {
				xml['foxml'].datastreamVersion(:ID => 'METHODMAP1.0', :MIMETYPE => 'text/xml', :FORMAT_URI => 'info:fedora/fedora-system:FedoraSDefMethodMap-1.0', :LABEL => 'Abstract Method Map') {
					xml['foxml'].xmlContent {
						xml['fmm'].MethodMap('name' => 'MethodMap - Collection of Objects', 'xmlns:fmm' => 'http://fedora.comm.nsdlib.org/service/methodmap') {
							xml['fmm'].Method('operationLabel' => 'An xml list of members in the collection', 'operationName' => 'list')
							xml['fmm'].Method('operationLabel' => 'An html representation of the collection', 'operationName' => 'view')
						}
					}
				}
			}
		}
	end
	foxml
end


def transform_item_dspace(item_info, collection_map)
	new_item = []
	field_info = {}
	item_info.each do |nick, value|
		
		if value.class == Hash # blank fields return an empty hash
			next
		else
			field_info = collection_map.fetch(nick)

			if field_info['namespace'] == "dspace"

				element = field_info['element']
				field_info['qualifier'] ? qualifier = field_info['qualifier'] : qualifier = "none"
				# label = field_info['label']
				# vocab = field_info['vocab']

				# remove white space, trailing semicolon
				value = value.strip.chomp(";")

				# parse multi-value fields and exclude transcript, description, extent
				if (value.include? ";") && (element != "transcript") \
					&& (element != "description") \
					&& (qualifier != "extent")

					value.split(";").each do |v|
						# field = "<dcvalue element=\"#{element}\" qualifier=\"#{qualifier}\" label=\"#{label}\">"
						field = "<dcvalue element=\"#{element}\" qualifier=\"#{qualifier}\">"
						field << "#{v.strip.gsub('&', '&amp;')}</dcvalue>" # strip whitespace, escape ampersands
						new_item << field
					end

				else # single value fields and exceptions
					# field = "<dcvalue element=\"#{element}\" qualifier=\"#{qualifier}\" label=\"#{label}\">"
					field = "<dcvalue element=\"#{element}\" qualifier=\"#{qualifier}\">"
					field << "#{value.gsub('&', '&amp;')}</dcvalue>" # escape ampersands
					new_item << field
				end

			else
				next # skip non-dspace fields
			end
		end
	end
	new_item
end


def get_compound_object_info(cdm_url, collection_alias, item_pointer)
	cdm_compound_object_info_url = cdm_url + "dmGetCompoundObjectInfo/#{collection_alias}/#{item_pointer}/xml"
	compound_object_info = Nokogiri::XML(open(cdm_compound_object_info_url))
end


def get_compound_object_items(compound_object_info)
	compound_object_items = compound_object_info.xpath("//pageptr/text()")
end


def construct_new_file_name(item_info, page_num)
	cdm_file_name = item_info.fetch("find").split(".")
	original_file_name = item_info.fetch("file").split(".")
	new_file_name = "#{original_file_name[0]}_cdm_%03d.#{cdm_file_name[1]}" % page_num
end

def download_file_dspace(object_download_dir, new_file_name, cdm_get_file_url, collection_alias, pointer)
	File.open(File.join(object_download_dir, new_file_name), "wb") do |saved_file|
		open(File.join(cdm_get_file_url, collection_alias, pointer.to_s), "rb") do |read_file|
			saved_file.write(read_file.read)
		end
	end
end


### IRB Methods for updating UH Metadata Map Google Doc

def export_default_metadata_map(download_dir = "/Users/weidnera/Desktop")
	require 'open-uri'
	require 'fileutils'
	require 'json'
	require 'nokogiri'
	require 'yaml'
	admin_config = YAML::load_file(File.join(__dir__, 'config.yml'))
	meta_config = YAML::load_file(File.join(__dir__, 'config_fedora.yml'))
	server = admin_config['cdm']['server']
	port = admin_config['cdm']['port']
	cdm_url = "http://#{server}:#{port}/dmwebservices/index.php?q="
	meta_map_config = meta_config['meta_map']
	meta_map_file = ""
	meta_map_config.each do |field|
		field['namespace'] ? namespace = field['namespace'] : namespace = ""
		field['map'] ? map = field['map'] : map = ""
		field['label'] ? label = field['label'] : label = ""
		field['type'] ? type = field['type'] : type = ""
		field['vocab'] ? vocab = field['vocab'] : vocab = ""
		meta_map_file += "#{label}\t#{namespace}\t#{map}\t#{type}\t#{vocab}\n"
	end
	File.open("#{download_dir}/default_map.txt", 'w') {|f| f.write(meta_map_file) }
end

def export_dspace_metadata_map(download_dir = "/Users/weidnera/Desktop")
	require 'open-uri'
	require 'fileutils'
	require 'json'
	require 'nokogiri'
	require 'yaml'
	admin_config = YAML::load_file(File.join(__dir__, 'config.yml'))
	meta_config = YAML::load_file(File.join(__dir__, 'config_dspace.yml'))
	server = admin_config['cdm']['server']
	port = admin_config['cdm']['port']
	cdm_url = "http://#{server}:#{port}/dmwebservices/index.php?q="
	meta_map_config = meta_config['meta_map']
	meta_map_file = ""
	unused_fields = []
	meta_map_config.each do |field|
		if field['namespace'] == "dspace"
			field['qualifier'].nil? ? qualifier = "none" : qualifier = field['qualifier']
			field['item_level'].nil? ? item_level = "" : item_level = field['item_level']
			meta_map_file += "#{field['label']}\t#{field['element']}\t#{qualifier}\t#{item_level}\n"
		else
			unused_fields << field['label']
		end
	end
	meta_map_file += "\n\nUnused Fields\n"
	unused_fields.each {|field| meta_map_file += "#{field}\n"}
	File.open("#{download_dir}/dspace_map.txt", 'w') { |f| f.write(meta_map_file) }
end

