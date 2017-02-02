RSpec.configure do |config|

  config.use_transactional_fixtures = false
  
  config.before(:suite) do
    DatabaseCleaner.clean_with(:truncation)
    
    http = Net::HTTP::new('zap', 80, '10.0.2.2', 8080)
    http.get('/JSON/core/action/newSession')
    http.get('/JSON/context/action/includeInContext/?contextName=Default+Context&regex=http://127.0.0.1:1900/.*')
  end
  
  config.before(:each) do
    DatabaseCleaner.strategy = :truncation
    DatabaseCleaner.start
  end
  
  config.append_after(:each) do
    http = Net::HTTP::new('zap', 80, '10.0.2.2', 8080)

    seconds_queue_has_been_zero = 0
    while seconds_queue_has_been_zero <= 5 do
      sleep(1)

      active_scan_queue = JSON.parse(http.get('/JSON/pscan/view/recordsToScan').body)['recordsToScan'].to_i

      if active_scan_queue == 0
        seconds_queue_has_been_zero += 1
      else
        seconds_queue_has_been_zero = 0
      end
    end
    
    DatabaseCleaner.clean
  end
  
  config.after(:suite) do |suite|
    http = Net::HTTP::new('zap', 80, '10.0.2.2', 8080)
    
    html_report = http.get('/OTHER/core/other/htmlreport').body
    xml_report = http.get('/OTHER/core/other/xmlreport').body

    results_filename = "report"

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
  end
end
