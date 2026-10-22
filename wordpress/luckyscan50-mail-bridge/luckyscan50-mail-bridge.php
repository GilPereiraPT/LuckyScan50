<?php
/**
 * Plugin Name: LuckyScan50 Mail Bridge
 * Description: Ponte de email e administração privada das estatísticas e licenças da API LuckyScan50.
 * Version: 1.1.0
 * Requires at least: 6.0
 * Requires PHP: 7.4
 * Author: LuckyScan50
 */
defined('ABSPATH') || exit;
require_once __DIR__ . '/app-services-admin.php';

final class LuckyScan50_Mail_Bridge {
    const OPTION = 'luckyscan50_mail_bridge_key';
    const FROM = 'luckyscan50@gmail.com';
    const LINK_HOST = 'luckyscan50-api.policlinicosdesantoandre.com';

    public static function table() {
        global $wpdb;
        return $wpdb->prefix . 'luckyscan50_mail_delivery';
    }

    public static function activate() {
        global $wpdb;
        require_once ABSPATH . 'wp-admin/includes/upgrade.php';
        $table = self::table();
        $collate = $wpdb->get_charset_collate();
        dbDelta("CREATE TABLE $table (
            delivery_id varchar(64) NOT NULL,
            fingerprint varchar(64) NOT NULL,
            state varchar(16) NOT NULL,
            created_at datetime NOT NULL,
            PRIMARY KEY  (delivery_id),
            KEY created_at (created_at)
        ) $collate;");
        if (!get_option(self::OPTION)) {
            add_option(self::OPTION, wp_generate_password(64, false, false), '', false);
        }
    }

    public static function key() {
        return defined('LUCKYSCAN50_MAIL_BRIDGE_KEY')
            ? (string) LUCKYSCAN50_MAIL_BRIDGE_KEY : (string) get_option(self::OPTION, '');
    }

    public static function authorize($request) {
        if (!is_ssl()) {
            return new WP_Error('https_required', 'HTTPS obrigatório.', array('status' => 403));
        }
        $given = (string) $request->get_header('x-luckyscan50-key');
        $expected = self::key();
        if (strlen($expected) < 32 || strlen($given) > 128 ||
            !hash_equals(hash('sha256', $expected), hash('sha256', $given))) {
            return new WP_Error('unauthorized', 'Pedido não autorizado.', array('status' => 401));
        }
        return true;
    }

    public static function register_routes() {
        register_rest_route('luckyscan50/v1', '/mail', array(
            'methods' => 'POST', 'callback' => array(__CLASS__, 'send'),
            'permission_callback' => array(__CLASS__, 'authorize'),
        ));
    }

    public static function validate($data) {
        if (!is_array($data) || array_diff(array_keys($data),
            array('deliveryId', 'to', 'subject', 'body', 'unsubscribeUrl'))) {
            return false;
        }
        foreach (array('deliveryId', 'to', 'subject', 'body', 'unsubscribeUrl') as $field) {
            if (!isset($data[$field]) || !is_string($data[$field])) { return false; }
        }
        if (!preg_match('/\A[a-f0-9]{64}\z/', $data['deliveryId']) ||
            !is_email($data['to']) || strlen($data['to']) > 254 ||
            preg_match('/[\r\n]/', $data['to'] . $data['subject']) ||
            strlen($data['subject']) > 240 || strpos($data['subject'], 'LuckyScan50') === false ||
            strlen($data['body']) < 1 || strlen($data['body']) > 64000 ||
            strlen($data['unsubscribeUrl']) > 2048 ||
            preg_match('/[\r\n<>]/', $data['unsubscribeUrl'])) {
            return false;
        }
        $url = wp_parse_url($data['unsubscribeUrl']);
        return is_array($url) && isset($url['scheme'], $url['host'], $url['path']) &&
            $url['scheme'] === 'https' && $url['host'] === self::LINK_HOST &&
            $url['path'] === '/v1/email/unsubscribe' &&
            (!isset($url['port']) || $url['port'] === 443) &&
            !isset($url['user']) && !isset($url['pass']) && !isset($url['fragment']);
    }

    public static function response($accepted, $duplicate = false) {
        $response = new WP_REST_Response(array(
            'accepted' => $accepted, 'duplicate' => $duplicate, 'provider' => 'wordpress',
        ), 200);
        $response->header('Cache-Control', 'no-store');
        return $response;
    }

    public static function send($request) {
        global $wpdb;
        if (strlen($request->get_body()) > 98304) {
            return new WP_Error('payload_too_large', 'Pedido demasiado grande.', array('status' => 413));
        }
        $data = $request->get_json_params();
        if (!self::validate($data)) {
            return new WP_Error('invalid_payload', 'Pedido inválido.', array('status' => 400));
        }
        $table = self::table();
        $id = $data['deliveryId'];
        // Fixed field order makes the content fingerprint independent of JSON key order.
        $fingerprint = hash('sha256', wp_json_encode(array(
            $data['to'], $data['subject'], $data['body'], $data['unsubscribeUrl'],
        )));
        $lock = 'ls50_mail_' . substr(hash('sha256', $table), 0, 24);
        if ((int) $wpdb->get_var($wpdb->prepare('SELECT GET_LOCK(%s,0)', $lock)) !== 1) {
            return new WP_Error('busy', 'Tente mais tarde.', array('status' => 429));
        }
        try {
            $old = $wpdb->get_row($wpdb->prepare("SELECT * FROM $table WHERE delivery_id=%s", $id), ARRAY_A);
            if ($old) {
                if (!hash_equals($old['fingerprint'], $fingerprint)) {
                    return new WP_Error('delivery_conflict', 'Identificador já utilizado.', array('status' => 409));
                }
                if ($old['state'] === 'accepted') { return self::response(true, true); }
                return new WP_Error('delivery_uncertain', 'Entrega anterior requer verificação.', array('status' => 409));
            }
            $since = gmdate('Y-m-d H:i:s', time() - DAY_IN_SECONDS);
            $count = (int) $wpdb->get_var($wpdb->prepare("SELECT COUNT(*) FROM $table WHERE created_at>%s", $since));
            if ($count >= 200) {
                return new WP_Error('daily_limit', 'Limite de envio atingido.', array('status' => 429));
            }
            $inserted = $wpdb->insert($table, array(
                'delivery_id' => $id, 'fingerprint' => $fingerprint,
                'state' => 'pending', 'created_at' => gmdate('Y-m-d H:i:s'),
            ), array('%s', '%s', '%s', '%s'));
            if ($inserted !== 1) {
                return new WP_Error('storage_error', 'Não foi possível reservar a entrega.', array('status' => 503));
            }
            $headers = array(
                'From: LuckyScan50 <' . self::FROM . '>',
                'Reply-To: LuckyScan50 <' . self::FROM . '>',
                'Content-Type: text/plain; charset=UTF-8',
                'List-Unsubscribe: <' . $data['unsubscribeUrl'] . '>',
                'List-Unsubscribe-Post: List-Unsubscribe=One-Click',
            );
            try {
                $accepted = wp_mail($data['to'], $data['subject'], $data['body'], $headers);
            } catch (Throwable $error) {
                $accepted = false;
            }
            // Even a false return can follow an ambiguous transport error. Never
            // automatically send the same ID again without checking the mail log.
            $updated = $wpdb->update($table, array('state' => $accepted ? 'accepted' : 'uncertain'),
                array('delivery_id' => $id), array('%s'), array('%s'));
            if (!$accepted || $updated !== 1) {
                return new WP_Error('delivery_uncertain', 'O resultado do envio requer verificação.', array('status' => 409));
            }
            // Retain only fingerprints, never recipient addresses or message bodies.
            $cutoff = gmdate('Y-m-d H:i:s', time() - 30 * DAY_IN_SECONDS);
            $wpdb->query($wpdb->prepare("DELETE FROM $table WHERE created_at<%s", $cutoff));
            return self::response(true);
        } finally {
            $wpdb->get_var($wpdb->prepare('SELECT RELEASE_LOCK(%s)', $lock));
        }
    }

    public static function menu() {
        add_options_page('LuckyScan50 Mail Bridge', 'LuckyScan50 Mail', 'manage_options',
            'luckyscan50-mail', array(__CLASS__, 'settings'));
    }

    public static function settings() {
        if (!current_user_can('manage_options')) { return; }
        if (isset($_POST['rotate_key'])) {
            check_admin_referer('luckyscan50_rotate_key');
            if (!defined('LUCKYSCAN50_MAIL_BRIDGE_KEY')) {
                update_option(self::OPTION, wp_generate_password(64, false, false), false);
            }
        }
        echo '<div class="wrap"><h1>LuckyScan50 Mail Bridge</h1>';
        echo '<p>Remetente: <strong>' . esc_html(self::FROM) . '</strong>. O envio usa a ligação correspondente no FluentSMTP.</p>';
        echo '<p>Copie estes dois valores para a configuração privada da API. Não os coloque na APK nem em capturas de ecrã partilhadas.</p>';
        echo '<p><label>LUCKYSCAN_WORDPRESS_MAIL_URL</label><br><input class="large-text" readonly value="' . esc_attr(rest_url('luckyscan50/v1/mail')) . '"></p>';
        echo '<p><label>LUCKYSCAN_WORDPRESS_MAIL_KEY</label><br><input class="large-text" readonly autocomplete="off" value="' . esc_attr(self::key()) . '"></p>';
        echo '<p>A chave autoriza apenas este serviço de email. Não é a palavra-passe do WordPress ou do Gmail.</p>';
        if (!defined('LUCKYSCAN50_MAIL_BRIDGE_KEY')) {
            echo '<form method="post">';
            wp_nonce_field('luckyscan50_rotate_key');
            submit_button('Gerar nova chave (invalida a anterior)', 'secondary', 'rotate_key');
            echo '</form>';
        }
        echo '<p>Uma resposta aceite indica que wp_mail processou o pedido; confirme a receção na caixa de correio e nos registos do FluentSMTP.</p></div>';
    }
}

register_activation_hook(__FILE__, array('LuckyScan50_Mail_Bridge', 'activate'));
add_action('rest_api_init', array('LuckyScan50_Mail_Bridge', 'register_routes'));
add_action('admin_menu', array('LuckyScan50_Mail_Bridge', 'menu'));
