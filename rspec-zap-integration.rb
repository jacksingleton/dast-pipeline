require 'rspec/rails'
require 'capybara/rails'
require 'database_cleaner'
require 'net/http'
require 'fileutils'

RSpec.configure do |config|

  config.use_transactional_fixtures = false

  config.before(:each) do
    DatabaseCleaner.strategy = :truncation
    DatabaseCleaner.start

    http = Net::HTTP::new('zap', 80, '10.0.2.2', 8080)
    http.get('/JSON/core/action/newSession')
  end
    
  config.append_after(:each) do |example|
    http = Net::HTTP::new('zap', 80, '10.0.2.2', 8080)
    
    current_scan_response = http.get("/JSON/ascan/action/scan/?url=#{Capybara.app_host}") 
    current_scan = JSON.parse(current_scan_response.body)['scan']

    while true do
      sleep(1)
      json = JSON.parse(http.get('/JSON/ascan/view/scans/?zapapiformat=JSON').body)
      scans = json['scans']

      break if scans.empty?
      
      done = scans.any? do |scan|
        scan['id'] == current_scan && scan['state'] == 'FINISHED'
      end

      break if done
    end

    html_report = http.get('/OTHER/core/other/htmlreport').body
    xml_report = http.get('/OTHER/core/other/xmlreport').body

    group_desc = example.metadata[:example_group][:description].gsub(' ', '_')
    example_desc = example.metadata[:description].gsub(' ', '_')
    results_filename = "#{group_desc}-#{example_desc}"

    if !Hash.from_xml(xml_report)['OWASPZAPReport']['site']['alerts'].nil?
      result_dir = 'zap'
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
