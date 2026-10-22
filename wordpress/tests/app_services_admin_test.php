<?php
/** Mock-only admin/API checks; never contact WordPress or the live backend. */
require __DIR__ . '/mail_bridge_test.php';
$can_manage = true; $nonce_valid = true; $requests = array();
$api_fixture = array('status' => 200, 'body' => array('installations' => 1, 'active7Days' => 1, 'daily' => array()));
function current_user_can($capability) { global $can_manage; return $can_manage && $capability === 'manage_options'; }
function is_wp_error($value) { return $value instanceof WP_Error; }
function wp_safe_remote_request($url, $args) {
    global $requests, $api_fixture;
    $requests[] = array('url' => $url, 'args' => $args);
    return $api_fixture;
}
function wp_remote_retrieve_response_code($response) { return $response['status']; }
function wp_remote_retrieve_body($response) { return json_encode($response['body']); }
function nocache_headers() {}
function check_admin_referer($action) {
    global $nonce_valid;
    if (!$nonce_valid || $action !== 'luckyscan50_app_services') { throw new Exception('Invalid nonce'); }
}
function wp_nonce_field($action) { echo '<input name="nonce" value="test">'; }
function submit_button($text, $class = '', $name = '', $wrap = true) { echo '<button>' . htmlspecialchars($text) . '</button>'; }
function esc_html($value) { return htmlspecialchars((string) $value, ENT_QUOTES); }
function esc_attr($value) { return esc_html($value); }
function wp_unslash($value) { return stripslashes($value); }
function update_option($key, $value, $autoload = null) { global $options; $options[$key] = $value; }
function delete_option($key) { global $options; unset($options[$key]); }

$admin_key = str_repeat('a', 43);
$options[LuckyScan50_App_Services_Admin::OPTION] = $admin_key;
$can_manage = false;
check(is_wp_error(LuckyScan50_App_Services_Admin::api('/admin/app/statistics')), 'Non-admin could contact API');
check(count($requests) === 0, 'Non-admin triggered network request');
ob_start(); LuckyScan50_App_Services_Admin::render(); $output = ob_get_clean();
check($output === '', 'Non-admin received private UI');
$can_manage = true;
check(is_wp_error(LuckyScan50_App_Services_Admin::api('/private/other')), 'Arbitrary route allowed');
check(count($requests) === 0, 'Arbitrary path made request');
$result = LuckyScan50_App_Services_Admin::api('/admin/app/statistics');
check($result['installations'] === 1, 'Statistics not returned');
check($requests[0]['url'] === 'https://luckyscan50-api.policlinicosdesantoandre.com/admin/app/statistics', 'Wrong API host');
check($requests[0]['args']['redirection'] === 0 && $requests[0]['args']['sslverify'] === true, 'Unsafe transport options');
check($requests[0]['args']['headers']['Authorization'] === 'Bearer ' . $admin_key, 'Admin key not kept server-side');

$_SERVER['REQUEST_METHOD'] = 'POST';
$_POST = array('ls_action' => 'create_owner');
$nonce_valid = false; $before = count($requests); $blocked = false;
try { LuckyScan50_App_Services_Admin::render(); } catch (Exception $error) { $blocked = true; }
check($blocked && count($requests) === $before, 'Owner mutation bypassed nonce');
$nonce_valid = true;
$_POST = array('ls_action' => 'save_token', 'api_token' => $admin_key);
ob_start(); LuckyScan50_App_Services_Admin::render(); $output = ob_get_clean();
check(strpos($output, $admin_key) === false, 'Stored admin key exposed in HTML');
check(count($requests) === $before, 'Saving key contacted API');

$activation_key = str_repeat('b', 43);
$api_fixture = array('status' => 201, 'body' => array('id' => 9, 'activationKey' => $activation_key));
$_POST = array('ls_action' => 'create_owner');
ob_start(); LuckyScan50_App_Services_Admin::render(); $output = ob_get_clean();
check(strpos($output, $activation_key) !== false, 'New activation key not shown once');
check(!in_array($activation_key, $options, true), 'Activation key saved in WordPress');
$last = end($requests);
check(json_decode($last['args']['body'], true) === array('action' => 'create'), 'Wrong owner creation request');

$api_fixture = array('status' => 200, 'body' => array('revoked' => true, 'id' => 9));
$_POST = array('ls_action' => 'revoke_owner', 'license_id' => '9');
ob_start(); LuckyScan50_App_Services_Admin::render(); $output = ob_get_clean();
$last = end($requests);
check(json_decode($last['args']['body'], true) === array('action' => 'revoke', 'id' => 9), 'Revocation ID not integer');
check(strpos($output, $admin_key) === false, 'Administrative key exposed after revocation');
echo "WordPress app-services admin checks passed (no live requests).\n";
