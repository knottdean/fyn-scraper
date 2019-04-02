require 'httparty'
require 'nokogiri'
require 'byebug'

@all_providers = Array.new
@all_courses = Array.new
@all_ucas_urls = Array.new
@base_url = 'https://digital.ucas.com'
@start_time = Time.new
HTTParty::Basement.default_options.update(verify: false)


# scrape pages for the IDs of the providers.
# IDs are used in second scraping url
def scrape_ids

  total_providers = 114
  providers_per_page = 15.0
  page = 1
  last_page = (total_providers/providers_per_page).ceil

  while page <= last_page
    page_url = "https://digital.ucas.com/search/results?SearchText=foundation+year&SubjectText=&SubjectText=&ProviderText=&ProviderText=&AutoSuggestType=&SearchType=&SortOrder=ProviderAtoZ&AcademicYearId=2019&ClearingOptOut=False&vacancy-rb=rba&filters=Destination_Undergraduate&DistanceFromPostcode=1mi&RegionDistancePostcode=&CurrentView=Provider&__RequestVerificationToken=1nBYW2kVKMrig8UqCs2jmIF1AA8-dYYrxhOdLraSg0nrtH1TKj5oNyPMBkD1rm3GuKfvN_wcuzkwjRoUqxtF6Vi7R-71MXshO_5IRVPAeis1&pageNumber=#{page}"
    unparsed_page = HTTParty.get(page_url)
    parsed_page = Nokogiri::HTML(unparsed_page)
    page_providers = parsed_page.css('h3.accordion__label')
    page_providers.each do |page_provider|
      provider = {
        name: page_provider.children[0].text.strip,
        id: page_provider.attributes['data-provider-id'].value
      }
      @all_providers << provider
    end
    page += 1
  end
end

# Writes all of the provider's names and IDs to a text file
def write_providers
  begin
    file = File.open('providers.text', 'w')
    @all_providers.each do |provider|
      file.write(provider[:name] + "\n")
      file.write(provider[:id] + "\n")
      file.write("\n")
    end
  ensure
    file.close unless file.nil?
  end
end

# Insert IDs in the url to get a list of all foundation years offered by the provider
def scrape_course_ucas_urls
  @all_providers.each do |provider|
    id = provider[:id]
    page_url = "https://digital.ucas.com/search/results?SearchText=foundation+year&SubjectText=&ProviderText=&AutoSuggestType=&SearchType=&SortOrder=ProviderAtoZ&AcademicYearId=2019&ClearingOptOut=False&vacancy-rb=rba&filters=Destination_Undergraduate&ProviderText=&SubjectText=&DistanceFromPostcode=1mi&RegionDistancePostcode=&CurrentView=Provider&__RequestVerificationToken=1nBYW2kVKMrig8UqCs2jmIF1AA8-dYYrxhOdLraSg0nrtH1TKj5oNyPMBkD1rm3GuKfvN_wcuzkwjRoUqxtF6Vi7R-71MXshO_5IRVPAeis1&GroupByProviderId=#{id}&GroupByDestination=Undergraduate&GroupByFrom=0&GroupBySize=5000"
    unparsed_page = HTTParty.get(page_url)
    parsed_page = Nokogiri::HTML(unparsed_page)
    tables = parsed_page.css('table.open')
    table_titles = tables.css('tr[1] > th').text
    table_text = tables.css('tr > td').text
    raw_name = tables.css('tr > th').text
    page_courses = parsed_page.css('a.course-summary')
    page_courses.each do |page_course|
      @all_ucas_urls << @base_url + page_course.attributes["href"].value
    end
  end
end

# for each course, pass the ucas url and parsed page to add_courses
def scrape_course_info
  counter = 1
  @all_ucas_urls.each do |url|
    unparsed_page = HTTParty.get(url)
    parsed_page = Nokogiri::HTML(unparsed_page)

    # pages with multiple options have to be treated differently
    options = parsed_page.css('a.academic-year-link-active').children[1].text.strip[0..1].strip

    # get each option's url, parse it, then pass the url and parsed page to add_courses
    if !(options.eql? "1")
      options = parsed_page.css("[class='course-option course-option--link']")
      option_urls = Array.new
      options.each do |option|
        option_urls << @base_url ++ option.attributes["href"].value
      end
      option_urls.each do |option_url|
        unparsed_option_page = HTTParty.get(option_url)
        parsed_option_page = Nokogiri::HTML(unparsed_option_page)
        add_courses(option_url, counter, parsed_option_page)
      end
    end

    # if only one option, pass straight to add_courses
    if (options.eql? "1")
      add_courses(url, counter, parsed_page)
    end

    counter += 1
  end
end

# gets the given course's information and appends it to the array of all courses
def add_courses(url, counter, parsed_page)
  all_paragraphs = parsed_page.xpath '//p' # all <p> on the page
  paragraph_number = 8 # The description paragraph for most pages

  # get the course's description
  course_description = ""
  while !all_paragraphs[paragraph_number].text.eql? "Qualification" do
    course_description += all_paragraphs[paragraph_number].text.strip
    course_description += "\n\n"
    paragraph_number += 1
  end
  # some pages are set up differently
  if course_description.empty?
    course_description = all_paragraphs[7].text
  else
    course_description = "No course description"
  end
  course_description = course_description.strip

  # if it exists, get the provider's url for the course
  provider_url = ""
  if !parsed_page.at_css('[id="ProviderCourseUrl"]').nil?
    provider_url = parsed_page.at_css('[id="ProviderCourseUrl"]').attributes["href"].value
  else
    provide_url = "No url available"
  end

  department = ""
  if !parsed_page.css('span').css('[id="contact_Title"]')[0].nil?
    department = parsed_page.css('span').css('[id="contact_Title"]')[0].text
  else
    department = "No department available"
  end

  email = ""
  if !parsed_page.at_css('.contact-email').nil?
    email = parsed_page.at_css('.contact-email').attributes["href"].value
  else
    email = "No email available"
  end

  requirements = ""
  if !parsed_page.css('section').css('[id="entry-requirements-section"]').nil?
    requirements += parsed_page.css('section').css('[id="entry-requirements-section"]').css('th.column-width--30pc').text
    requirements += parsed_page.css('section').css('[id="entry-requirements-section"]').css('td.column-width--20pc').text
    requirements += parsed_page.css('section').css('[id="entry-requirements-section"]').css('td.column-width--70pc').text
    requirements += parsed_page.css('section').css('[id="entry-requirements-section"]').css('td.column-width--50pc').text
  else
    requirements = "No requirements on the page"
  end

  # if a contact exists then
  contact = ""
  if !parsed_page.at_css('[id="contact_Phone"]').nil?
    contact = parsed_page.at_css('[id="contact_Phone"]').text
  else
    contact = "no contact number available"
  end

  # course object with all of the scraped info
  course = {
    title: parsed_page.css('h1.search-result__result-provider').children[0].text.strip,
    qualification: all_paragraphs[paragraph_number+1].text,
    provider: parsed_page.css('h1.search-result__result-provider').children[1].text.strip,
    provider_url: provider_url,
    ucas_url: url,
    description: course_description,
    study_mode: all_paragraphs[paragraph_number+3].text,
    location: all_paragraphs[paragraph_number+5].text,
    start_date: all_paragraphs[paragraph_number+7].text,
    duration: all_paragraphs[paragraph_number+9].text,
    department: department,
    requirements: requirements,
    institution: parsed_page.css('td[id="institution-code"]').text,
    course_code: parsed_page.css('td[id="application-code"]').text,
    contact_number: contact,
    email: email,
    delivery: delivery
  }

  puts "Course #{counter}: #{course[:title]} #{course[:provider]}, delivery: #{course[:delivery]}"
  @all_courses << course
end

# Writes all courses to text file
def write_courses
  begin
    file = File.open('courses.text', 'w')
    @all_courses.each do |course|
      file.write("Title: " + course[:title] + "\n")
      file.write("Qualification: " + course[:qualification] + "\n")
      file.write("Provider: " + course[:provider] + "\n")
      file.write("Provider URL: " + course[:provider_url] + "\n")
      file.write("UCAS URL: " + course[:ucas_url] + "\n")
      file.write("Description: " + course[:description] + "\n")
      file.write("Study Mode: " + course[:study_mode] + "\n")
      file.write("Location: " + course[:location] + "\n")
      file.write("Start Date: " + course[:start_date] + "\n")
      file.write("Duration " + course[:duration] + "\n")
      file.write("Department: " + course[:department] + "\n")
      file.write("Requirements: " + course[:requirements] + "\n")
      file.write("Institution Code " + course[:institution] + "\n")
      file.write("Course Code: " + course[:course_code] + "\n")
      file.write("Contact number: " + course[:contact_number] + "\n")
      file.write("Email address: " + course[:email])
      file.write("\n")
    end
  ensure
    file.close unless file.nil?
  end
end

def display_times
  puts "Start Time: #{@start_time}"
  puts "End Time: #{Time.new}"
end

scrape_ids
write_providers
scrape_course_ucas_urls
scrape_course_info
write_courses
display_times
