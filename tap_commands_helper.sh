#!/bin/bash
#
# TAP Commands Helper - Comandos de manutenção Bose
# Para uso com QuietComfort Ultra
#

BOSE_DFU="./target/release/bose-dfu"
FORCE_FLAG="--force"

echo "=============================================="
echo "  Bose TAP Commands - Modo Interativo"
echo "=============================================="
echo ""
echo "Este script ajuda a executar comandos TAP de manutenção."
echo "Comandos TAP são usados para diagnóstico e configuração."
echo ""

# Verificar se dispositivo está conectado
echo "Verificando dispositivo..."
if ! $BOSE_DFU list | grep -q "05a7"; then
    echo "❌ Nenhum dispositivo Bose detectado via USB"
    exit 1
fi

echo "✓ Dispositivo detectado"
echo ""

# Verificar se está em modo normal (TAP só funciona em modo normal)
if ! $BOSE_DFU info $FORCE_FLAG &>/dev/null; then
    echo "❌ Dispositivo está em DFU mode. TAP commands só funcionam em modo normal."
    echo ""
    echo "Para sair do DFU mode:"
    echo "  $BOSE_DFU leave-dfu $FORCE_FLAG"
    exit 1
fi

echo "=============================================="
echo "Comandos TAP Conhecidos"
echo "=============================================="
echo ""
echo "COMANDOS DE INFORMAÇÃO:"
echo "  vr          - Versão do firmware"
echo "  sn          - Número de série"
echo "  pl          - Product Line (modelo)"
echo ""
echo "COMANDOS EXPERIMENTAIS (podem não funcionar):"
echo "  bt          - Status/comandos Bluetooth"
echo "  bt reset    - Reset do subsistema Bluetooth"
echo "  bt clear    - Limpar memória de pareamentos"
echo "  bt pair     - Forçar modo de pareamento"
echo "  reset       - Reset geral do dispositivo"
echo "  shipmode    - Modo de transporte (desliga bateria)"
echo ""
echo "COMANDOS PERSONALIZADOS:"
echo "  Você pode tentar qualquer comando de 2 letras"
echo "  Exemplos de service manuals: lc, db, fw, etc."
echo ""
echo "=============================================="
echo ""

# Função para executar comando com tratamento de erros
execute_tap() {
    local cmd="$1"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Executando: $cmd"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Criar script temporário que envia o comando e sai
    TMP_SCRIPT=$(mktemp)
    echo "$cmd" > "$TMP_SCRIPT"
    echo "." >> "$TMP_SCRIPT"

    timeout 10 $BOSE_DFU tap $FORCE_FLAG < "$TMP_SCRIPT" 2>&1 || {
        echo "⚠️  Timeout ou erro ao executar comando"
    }

    rm -f "$TMP_SCRIPT"
    echo ""
}

# Menu de opções
while true; do
    echo ""
    echo "Escolha uma opção:"
    echo "  1. Executar comandos de informação básica"
    echo "  2. Tentar comandos de Bluetooth/reset"
    echo "  3. Executar comando TAP personalizado"
    echo "  4. Modo interativo completo (manual)"
    echo "  5. Sair"
    echo ""
    read -p "Opção: " -n 1 -r
    echo

    case $REPLY in
        1)
            echo ""
            echo "Executando comandos de informação..."
            execute_tap "vr"
            execute_tap "sn"
            execute_tap "pl"
            ;;
        2)
            echo ""
            echo "⚠️  ATENÇÃO: Estes comandos são experimentais!"
            echo ""
            read -p "Continuar? (s/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[SsYy]$ ]]; then
                execute_tap "bt"

                read -p "Tentar 'bt reset'? (s/N): " -n 1 -r
                echo
                [[ $REPLY =~ ^[SsYy]$ ]] && execute_tap "bt reset"

                read -p "Tentar 'bt clear' (limpa pareamentos)? (s/N): " -n 1 -r
                echo
                [[ $REPLY =~ ^[SsYy]$ ]] && execute_tap "bt clear"

                read -p "Tentar 'bt pair' (força pareamento)? (s/N): " -n 1 -r
                echo
                [[ $REPLY =~ ^[SsYy]$ ]] && execute_tap "bt pair"

                read -p "Tentar 'reset' geral? (s/N): " -n 1 -r
                echo
                [[ $REPLY =~ ^[SsYy]$ ]] && execute_tap "reset"
            fi
            ;;
        3)
            echo ""
            read -p "Digite o comando TAP (ex: 'vr', 'bt', etc.): " TAP_CMD
            execute_tap "$TAP_CMD"
            ;;
        4)
            echo ""
            echo "Entrando em modo interativo..."
            echo "Digite comandos TAP diretamente."
            echo "Para sair, digite: ."
            echo ""
            $BOSE_DFU tap $FORCE_FLAG
            ;;
        5)
            echo "Saindo..."
            exit 0
            ;;
        *)
            echo "Opção inválida"
            ;;
    esac
done
