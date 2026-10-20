<?php
/** Isolated contract tests: no WordPress instance, database or real emails. */
define('ABSPATH', __DIR__ . '/');
define('ARRAY_A', 'ARRAY_A');
define('DAY_IN_SECONDS', 86400);
$options = array('luckyscan50_mail_bridge_key' => str_repeat('k', 64));
$mail_count = 0;
$mail_success = true;
$last_headers = array();
function get_option($key, $default = '') { global $options; return $options[$key] ?? $default; }
function is_ssl() { return true; }
function is_email($value) { return filter_var($value, FILTER_VALIDATE_EMAIL); }
function wp_parse_url($value) { return parse_url($value); }
function wp_json_encode($value) { return json_encode($value); }
function register_activation_hook($file, $callback) {}
function add_action($hook, $callback) {}
function register_rest_route($namespace, $route, $args) {
    check(isset($args['permission_callback']), 'REST permission callback missing');
}
function wp_mail($to, $subject, $body, $headers) {
    global $mail_count, $mail_success, $last_headers;
    $mail_count++;
    $last_headers = $headers;
    return $mail_success;
}
class WP_Error {
    public $code, $data;
    public function __construct($code, $message, $data) { $this->code = $code; $this->data = $data; }
}
class WP_REST_Response {
    public $data, $status;
    public function __construct($data, $status) { $this->data = $data; $this->status = $status; }
    public function header($name, $value) {}
}
class RequestFixture {
    public $data, $key;
    public function __construct($data, $key = null) {
        $this->data = $data; $this->key = $key ?? str_repeat('k', 64);
    }
    public function get_header($name) { return $this->key; }
    public function get_body() { return json_encode($this->data); }
    public function get_json_params() { return $this->data; }
}
class DatabaseFixture {
    public $prefix = 'wp_', $rows = array(), $locked = false;
    public function prepare($sql, ...$args) {
        foreach ($args as $arg) { $sql = preg_replace('/%s/', "'" . $arg . "'", $sql, 1); }
        return $sql;
    }
    public function get_var($sql) {
        if (strpos($sql, 'GET_LOCK') !== false) { $this->locked = true; return 1; }
        if (strpos($sql, 'RELEASE_LOCK') !== false) { $this->locked = false; return 1; }
        if (strpos($sql, 'COUNT(*)') !== false) { return count($this->rows); }
        throw new Exception('Unexpected SQL');
    }
    public function get_row($sql, $mode) {
        preg_match("/delivery_id='([a-f0-9]+)'/", $sql, $match);
        return $this->rows[$match[1]] ?? null;
    }
    public function insert($table, $row, $formats) {
        if (isset($this->rows[$row['delivery_id']])) { return 0; }
        $this->rows[$row['delivery_id']] = $row;
        return 1;
    }
    public function update($table, $values, $where, $formats, $where_formats) {
        $this->rows[$where['delivery_id']] = array_merge($this->rows[$where['delivery_id']], $values);
        return 1;
    }
    public function query($sql) { return 0; }
}
function check($condition, $message) {
    if (!$condition) { throw new Exception($message); }
}
require dirname(__DIR__) . '/luckyscan50-mail-bridge/luckyscan50-mail-bridge.php';

$wpdb = new DatabaseFixture();
$data = array(
    'deliveryId' => str_repeat('a', 64),
    'to' => 'reader@example.pt', 'subject' => 'Confirme os avisos do LuckyScan50',
    'body' => "Confirme o seu email.\nCancelar: https://example.test",
    'unsubscribeUrl' => 'https://luckyscan50-api.policlinicosdesantoandre.com/v1/email/unsubscribe?id=x&token=y',
);
LuckyScan50_Mail_Bridge::register_routes();
check(LuckyScan50_Mail_Bridge::authorize(new RequestFixture($data)) === true, 'Valid key rejected');
$unauthorized = LuckyScan50_Mail_Bridge::authorize(new RequestFixture($data, 'wrong'));
check($unauthorized instanceof WP_Error && $unauthorized->data['status'] === 401, 'Wrong key accepted');
check(LuckyScan50_Mail_Bridge::validate($data), 'Valid payload rejected');

foreach (array(
    array('to', "reader@example.pt\r\nBcc: victim@example.pt"),
    array('subject', "LuckyScan50\r\nBcc: victim@example.pt"),
    array('unsubscribeUrl', $data['unsubscribeUrl'] . "\r\nBcc: victim@example.pt"),
    array('unsubscribeUrl', 'https://untrusted.example/v1/email/unsubscribe'),
    array('unsubscribeUrl', 'https://luckyscan50-api.policlinicosdesantoandre.com/other'),
    array('deliveryId', 'bad'), array('body', ''), array('body', str_repeat('a', 64001)),
) as $mutation) {
    $bad = $data; $bad[$mutation[0]] = $mutation[1];
    check(!LuckyScan50_Mail_Bridge::validate($bad), 'Invalid payload accepted: ' . $mutation[0]);
}
$bad = $data; $bad['attachments'] = array('/private/file');
check(!LuckyScan50_Mail_Bridge::validate($bad), 'Unexpected attachment accepted');

$first = LuckyScan50_Mail_Bridge::send(new RequestFixture($data));
check($first instanceof WP_REST_Response && $first->data['accepted'], 'Delivery not accepted');
check($mail_count === 1 && !$wpdb->locked, 'Wrong send count or leaked lock');
check(in_array('From: LuckyScan50 <luckyscan50@gmail.com>', $last_headers), 'Wrong From');
check(in_array('List-Unsubscribe-Post: List-Unsubscribe=One-Click', $last_headers), 'Missing unsubscribe header');
check(!isset($wpdb->rows[$data['deliveryId']]['to']), 'Recipient stored in bridge table');
$duplicate = LuckyScan50_Mail_Bridge::send(new RequestFixture($data));
check($duplicate->data['duplicate'] && $mail_count === 1, 'Duplicate resent');
$changed = $data; $changed['body'] .= ' altered';
$conflict = LuckyScan50_Mail_Bridge::send(new RequestFixture($changed));
check($conflict instanceof WP_Error && $conflict->data['status'] === 409, 'Conflicting ID accepted');

$mail_success = false;
$data['deliveryId'] = str_repeat('b', 64);
$failed = LuckyScan50_Mail_Bridge::send(new RequestFixture($data));
check($failed instanceof WP_Error && $failed->data['status'] === 409, 'Ambiguous failure treated as safe retry');
$count = $mail_count;
LuckyScan50_Mail_Bridge::send(new RequestFixture($data));
check($mail_count === $count, 'Ambiguous delivery automatically repeated');

for ($i = 0; count($wpdb->rows) < 200; $i++) {
    $id = hash('sha256', 'quota-' . $i);
    $wpdb->rows[$id] = array('delivery_id' => $id);
}
$data['deliveryId'] = str_repeat('c', 64);
$limited = LuckyScan50_Mail_Bridge::send(new RequestFixture($data));
check($limited instanceof WP_Error && $limited->data['status'] === 429, 'Quota not applied');
check(!$wpdb->locked, 'Quota rejection leaked lock');
echo "WordPress bridge contract checks passed (no live mail).\n";
