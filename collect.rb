require 'mysql2'
require 'net/ssh/gateway'

SSH_HOST = 'hostname'
SSH_USER = 'user'
SSH_PASS = 'pass'

DB_USER = 'user'
DB_PASS = 'pass'
DB_NAME = 'name'

FIELD_NAME = 'ssh_public_keys'

OUTPUT_DIR = '.'

# SSHポートフォワード
puts "Connect to ssh://#{SSH_USER}@#{SSH_HOST}"
gateway = Net::SSH::Gateway.new(
  SSH_HOST,
  SSH_USER,
  :password => SSH_PASS
)
port = gateway.open('127.0.0.1', 3306)

# 接続
puts "Connect to mysql://#{DB_USER}@localhost:#{port}/#{DB_NAME}"
client = Mysql2::Client.new(
  host: "127.0.0.1",
  username: DB_USER,
  password: DB_PASS,
  database: DB_NAME,
  port: port
)

puts "Collecting ssh public keys"

# SSH公開鍵のカスタムフィールドid取得
res = client.query("SELECT id FROM custom_fields WHERE name = '#{FIELD_NAME}'").first
unless res
  puts "カスタムフィールド '#{FIELD_NAME}' が見つかりませんでした"
  exit 1
end
field_id = res['id']

# 登録されている公開鍵取得
res = client.query("SELECT customized_id AS id, value FROM  custom_values WHERE custom_field_id = #{field_id}")
public_keys = Hash[res.select{|key| key['value'] && key['value'].size > 0}.map{|key| [key['id'], key['value'].strip]}]

# プロジェクトのidと識別子一覧取得
res = client.query("SELECT id, identifier FROM projects")
projects = res.map{|data| [data['id'], data['identifier']]}

# プロジェクトごとのメンバー一覧取得
project_members = projects.map do |project_id, identifier|
  res = client.query("SELECT user_id FROM members WHERE project_id = #{project_id}").map{|data| data['user_id']}
  [identifier, res]
end

# プロジェクトのメンバーが公開鍵を持っていたら追加
project_keys = Hash[project_members.map do |identifier, members|
  keys = members.map{|id| public_keys[id]}
  [identifier, keys.compact]
end]

# 接続閉じる
client.close
gateway.close(port)

# 書き出し
puts "Write to file (base path: #{File.expand_path(OUTPUT_DIR)})"
project_keys.each do |identifier, keys|
  File.open("#{OUTPUT_DIR}/#{identifier}.pub","w") do |file|
    keys.each{|key| file.puts key}
  end
end
puts "Done"
