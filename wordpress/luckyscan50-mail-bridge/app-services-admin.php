<?php
/** Private WordPress controls for the Python API. No public REST routes. */
defined('ABSPATH') || exit;

final class LuckyScan50_App_Services_Admin {
    const OPTION = 'luckyscan50_app_admin_token';
    const BASE = 'https://luckyscan50-api.policlinicosdesantoandre.com';

    public static function key() {
        return defined('LUCKYSCAN50_APP_ADMIN_TOKEN')
            ? (string) LUCKYSCAN50_APP_ADMIN_TOKEN : (string) get_option(self::OPTION, '');
    }

    public static function menu() {
        add_options_page('LuckyScan50 API', 'LuckyScan50 API', 'manage_options',
            'luckyscan50-app-services', array(__CLASS__, 'render'));
    }

    public static function api($path, $method = 'GET', $body = null) {
        if (!current_user_can('manage_options')) {
            return new WP_Error('forbidden', 'Acesso reservado à administração.', array('status' => 403));
        }
        $allowed = array('GET /admin/app/statistics', 'GET /admin/app/licenses', 'POST /admin/app/licenses');
        if (!in_array($method . ' ' . $path, $allowed, true)) {
            return new WP_Error('invalid_route', 'Operação não disponível.', array('status' => 400));
        }
        $key = self::key();
        if (!preg_match('/\A[A-Za-z0-9_-]{32,128}\z/', $key)) {
            return new WP_Error('not_configured', 'Configure a chave administrativa da API.', array('status' => 503));
        }
        $args = array('method' => $method, 'timeout' => 12, 'redirection' => 0,
            'sslverify' => true, 'limit_response_size' => 524288,
            'headers' => array('Authorization' => 'Bearer ' . $key, 'Content-Type' => 'application/json'));
        if ($body !== null) { $args['body'] = wp_json_encode($body); }
        $response = wp_safe_remote_request(self::BASE . $path, $args);
        if (is_wp_error($response)) {
            return new WP_Error('api_unavailable', 'Não foi possível contactar a API.', array('status' => 503));
        }
        $status = wp_remote_retrieve_response_code($response);
        $data = json_decode(wp_remote_retrieve_body($response), true);
        if (!in_array($status, array(200, 201), true) || !is_array($data)) {
            return new WP_Error('api_rejected', 'A API recusou o pedido. Verifique a chave e a instalação do pacote Python atualizado.', array('status' => 503));
        }
        return $data;
    }

    private static function form_button($action, $label, $id = null, $class = 'secondary') {
        echo '<form method="post" style="display:inline-block;margin:4px">';
        wp_nonce_field('luckyscan50_app_services');
        echo '<input type="hidden" name="ls_action" value="' . esc_attr($action) . '">';
        if ($id !== null) { echo '<input type="hidden" name="license_id" value="' . esc_attr($id) . '">'; }
        submit_button($label, $class, 'submit', false);
        echo '</form>';
    }

    public static function render() {
        if (!current_user_can('manage_options')) { return; }
        nocache_headers();
        $notice = ''; $error = null; $activation = null; $statistics = null; $licenses = null;
        if ($_SERVER['REQUEST_METHOD'] === 'POST') {
            check_admin_referer('luckyscan50_app_services');
            $action = isset($_POST['ls_action']) && is_string($_POST['ls_action']) ? wp_unslash($_POST['ls_action']) : '';
            if ($action === 'save_token' && !defined('LUCKYSCAN50_APP_ADMIN_TOKEN')) {
                $given = isset($_POST['api_token']) && is_string($_POST['api_token']) ? trim(wp_unslash($_POST['api_token'])) : '';
                if (preg_match('/\A[A-Za-z0-9_-]{32,128}\z/', $given)) {
                    update_option(self::OPTION, $given, false);
                    $notice = 'Chave administrativa guardada.';
                } else { $error = new WP_Error('invalid_key', 'Introduza uma chave válida com pelo menos 32 caracteres.', array('status' => 400)); }
            } elseif ($action === 'remove_token' && !defined('LUCKYSCAN50_APP_ADMIN_TOKEN')) {
                delete_option(self::OPTION);
                $notice = 'Chave administrativa removida deste WordPress.';
            } elseif ($action === 'create_owner') {
                $result = self::api('/admin/app/licenses', 'POST', array('action' => 'create'));
                if (is_wp_error($result)) { $error = $result; }
                elseif (isset($result['activationKey'], $result['id']) && is_string($result['activationKey'])) { $activation = $result; }
                else { $error = new WP_Error('invalid_response', 'Resposta de ativação inválida.', array('status' => 503)); }
            } elseif ($action === 'revoke_owner') {
                $id = isset($_POST['license_id']) && is_string($_POST['license_id']) ? wp_unslash($_POST['license_id']) : '';
                if (ctype_digit($id) && (int) $id > 0) {
                    $result = self::api('/admin/app/licenses', 'POST', array('action' => 'revoke', 'id' => (int) $id));
                    if (is_wp_error($result)) { $error = $result; } else { $notice = 'Licença revogada.'; }
                } else { $error = new WP_Error('invalid_id', 'Número de licença inválido.', array('status' => 400)); }
            } elseif ($action === 'refresh') {
                $statistics = self::api('/admin/app/statistics');
                $licenses = self::api('/admin/app/licenses');
                if (is_wp_error($statistics)) { $error = $statistics; $statistics = null; }
                if (is_wp_error($licenses)) { $error = $licenses; $licenses = null; }
            }
        }
        echo '<div class="wrap"><h1>LuckyScan50 — API e proprietário</h1>';
        if ($notice) { echo '<div class="notice notice-success"><p>' . esc_html($notice) . '</p></div>'; }
        if ($error) { echo '<div class="notice notice-error"><p>' . esc_html($error->get_error_message()) . '</p></div>'; }
        echo '<h2>Ligação privada à API</h2><p>Use o mesmo valor de <code>LUCKYSCAN_ADMIN_TOKEN</code> configurado no servidor Python. Esta chave é diferente da chave da ponte de email.</p>';
        echo '<p>Estado: <strong>' . (strlen(self::key()) >= 32 ? 'chave configurada' : 'por configurar') . '</strong>.</p>';
        if (!defined('LUCKYSCAN50_APP_ADMIN_TOKEN')) {
            echo '<form method="post">'; wp_nonce_field('luckyscan50_app_services');
            echo '<input type="hidden" name="ls_action" value="save_token"><label>Chave administrativa <input type="password" name="api_token" class="large-text" autocomplete="new-password" required></label>';
            submit_button('Guardar chave'); echo '</form>';
            if (self::key()) { self::form_button('remove_token', 'Remover chave deste WordPress'); }
        } else { echo '<p>Chave definida na configuração privada do WordPress.</p>'; }
        echo '<h2>Estatísticas e licenças</h2>';
        self::form_button('refresh', 'Consultar estatísticas e licenças', null, 'primary');
        self::form_button('create_owner', 'Criar chave de proprietário');
        if ($activation) {
            echo '<div class="notice notice-success"><p>Licença ' . esc_html($activation['id']) . ' criada. Guarde a chave agora: é apresentada uma única vez.</p><p><code>' . esc_html($activation['activationKey']) . '</code></p><p>Na app, mantenha premida a linha da versão no rodapé das Definições e introduza esta chave.</p></div>';
        }
        if (is_array($statistics)) {
            echo '<p>Instalações com partilha ativa: <strong>' . esc_html($statistics['installations'] ?? 0) . '</strong> · Ativas nos últimos 7 dias: <strong>' . esc_html($statistics['active7Days'] ?? 0) . '</strong></p>';
            echo '<p>Apenas instalações com consentimento. Retenção de 90 dias.</p><table class="widefat striped"><thead><tr><th>Dia UTC</th><th>Evento</th><th>Versão</th><th>Plataforma</th><th>Contagem</th></tr></thead><tbody>';
            foreach (($statistics['daily'] ?? array()) as $row) {
                if (!is_array($row)) { continue; }
                echo '<tr>';
                foreach (array('day', 'event', 'version', 'platform', 'count') as $column) { echo '<td>' . esc_html(is_scalar($row[$column] ?? null) ? $row[$column] : '') . '</td>'; }
                echo '</tr>';
            }
            echo '</tbody></table>';
        }
        if (is_array($licenses)) {
            echo '<h2>Últimas licenças de proprietário</h2><table class="widefat striped"><thead><tr><th>ID</th><th>Estado</th><th>Ação</th></tr></thead><tbody>';
            foreach (($licenses['licenses'] ?? array()) as $row) {
                if (!is_array($row) || !isset($row['id'])) { continue; }
                echo '<tr><td>' . esc_html($row['id']) . '</td><td>' . (!empty($row['revoked']) ? 'Revogada' : (!empty($row['bound']) ? 'Associada a uma instalação' : 'Por ativar')) . '</td><td>';
                if (empty($row['revoked'])) { self::form_button('revoke_owner', 'Revogar licença ' . $row['id'], $row['id']); }
                echo '</td></tr>';
            }
            echo '</tbody></table>';
        }
        echo '<p>A instalação deste plugin não instala o backend Python. Atualize também o pacote cPanel e configure as três variáveis dos serviços da app.</p></div>';
    }
}

add_action('admin_menu', array('LuckyScan50_App_Services_Admin', 'menu'));
