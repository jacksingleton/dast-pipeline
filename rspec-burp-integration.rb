require 'rspec/rails'
require 'capybara/rails'
require 'database_cleaner'
require 'net/http'
require 'fileutils'

RSpec.configure do |config|

  config.use_transactional_fixtures = false
  
  config.before(:suite) do
    DatabaseCleaner.clean_with(:truncation)
  end
  
  config.before(:each) do
    DatabaseCleaner.strategy = :truncation
    DatabaseCleaner.start

    http = Net::HTTP::new('10.0.2.2', 8090)
    http.get('/burp/restore')
  end
  
  config.append_after(:each) do |example|
    http = Net::HTTP::new('10.0.2.2', 8090)

    scope_req = Net::HTTP::Put.new(URI('http://10.0.2.2:8090/burp/target/scope'))
    scope_req.set_form_data({ 'url': Capybara.app_host })
    http.request(scope_req)

    Net::HTTP.post_form(URI("http://10.0.2.2:8090/burp/scanner/scans/active"), { 'baseUrl': Capybara.app_host }) 

    while true do
      sleep(1)
      
      percent_done = JSON.parse(http.get('/burp/scanner/status').body)['scanPercentage']

      break if percent_done == 100
    end

    html_report = http.get('/burp/report?reportType=HTML').body
    xml_report = http.get('/burp/report?reportType=XML').body

    group_desc = example.metadata[:example_group][:description].gsub(' ', '_')
    example_desc = example.metadata[:description].gsub(' ', '_')
    results_filename = "#{group_desc}-#{example_desc}"

    if !Hash.from_xml(xml_report)['issues']['issue'].nil?
      result_dir = 'burp'
      FileUtils::mkdir_p(result_dir)
      
      File.open(File.join(result_dir, "#{results_filename}.html"), 'w') do |fp|
        fp.write(html_report)
      end
      
      File.open(File.join(result_dir, "#{results_filename}.xml"), 'w') do |fp|
        fp.write(xml_report)
      end
    end
    
    DatabaseCleaner.clean
  end
end
