#!/bin/bash
#
# Script de Recuperação para Bose QuietComfort Ultra
# Problema: Falta de áudio no canal direito + botão Bluetooth danificado
#
# ATENÇÃO: Este dispositivo NÃO está oficialmente testado.
# Use por sua conta e risco. Pode brickar o dispositivo.
#

set -e

BOSE_DFU="./target/release/bose-dfu"
FORCE_FLAG="--force"

echo "=============================================="
echo "  Bose QuietComfort Ultra - Script de Recuperação"
echo "=============================================="
echo ""
echo "⚠️  AVISO: QC Ultra não está oficialmente testado"
echo "⚠️  Certifique-se de que:"
echo "   - Dispositivo está conectado via USB-C"
echo "   - Bateria > 20%"
echo "   - Cabo de DADOS (não apenas carregamento)"
echo ""
read -p "Continuar? (s/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[SsYy]$ ]]; then
    echo "Cancelado."
    exit 1
fi

echo ""
echo "=============================================="
echo "ETAPA 1: Listando dispositivos conectados"
echo "=============================================="
$BOSE_DFU list
echo ""

read -p "Você vê seu QuietComfort Ultra listado acima? (s/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[SsYy]$ ]]; then
    echo ""
    echo "❌ ERRO: Dispositivo não detectado."
    echo ""
    echo "Troubleshooting:"
    echo "  1. Verifique se o cabo USB-C é de DADOS"
    echo "  2. Tente outra porta USB"
    echo "  3. Reinicie o dispositivo (se possível)"
    echo "  4. No macOS: System Settings > Privacy & Security > Input Monitoring"
    exit 1
fi

echo ""
echo "=============================================="
echo "ETAPA 2: Obtendo informações do dispositivo"
echo "=============================================="
if $BOSE_DFU info $FORCE_FLAG 2>/dev/null; then
    echo "✓ Informações obtidas com sucesso"
else
    echo "⚠️  Não foi possível obter informações (normal se já estiver em DFU mode)"
fi
echo ""

echo "=============================================="
echo "ETAPA 3: Tentando comandos TAP de diagnóstico"
echo "=============================================="
echo ""
echo "Vamos tentar executar comandos TAP para:"
echo "  - Verificar estado do sistema"
echo "  - Tentar reset de subsistemas"
echo ""

# Função para executar comando TAP
run_tap_command() {
    local cmd="$1"
    local desc="$2"
    echo ""
    echo "Tentando: $desc"
    echo "> $cmd"

    # Criar arquivo temporário com o comando
    echo "$cmd" | timeout 5 $BOSE_DFU tap $FORCE_FLAG 2>&1 || true
}

if $BOSE_DFU info $FORCE_FLAG &>/dev/null; then
    echo ""
    echo "Comandos TAP disponíveis (alguns podem não funcionar):"
    echo ""

    # Comandos conhecidos
    run_tap_command "vr" "Versão do firmware"
    run_tap_command "sn" "Número de série"
    run_tap_command "pl" "Modelo do produto"

    echo ""
    read -p "Tentar comandos experimentais de reset/Bluetooth? (s/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[SsYy]$ ]]; then
        run_tap_command "bt" "Status Bluetooth"
        run_tap_command "bt reset" "Reset Bluetooth"
        run_tap_command "bt clear" "Limpar pareamentos"
        run_tap_command "bt pair" "Forçar modo pareamento"
        run_tap_command "reset" "Reset geral"
    fi
else
    echo "⚠️  Dispositivo não responde a comandos TAP (pode estar em DFU mode)"
fi

echo ""
echo "=============================================="
echo "ETAPA 4: SOLUÇÃO PRINCIPAL - Re-flash de Firmware"
echo "=============================================="
echo ""
echo "Esta é a solução que deve resolver o problema do canal direito."
echo "O re-flash vai:"
echo "  1. Limpar o 'dirty flag' do DSP de áudio"
echo "  2. Reinicializar todos os subsistemas"
echo "  3. Restaurar configurações de fábrica"
echo ""
echo "AVISOS:"
echo "  ⚠️  NÃO desconecte o cabo durante o processo"
echo "  ⚠️  Processo pode levar vários minutos"
echo "  ⚠️  Risco de brick se interrompido"
echo ""

read -p "Continuar com re-flash de firmware? (s/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[SsYy]$ ]]; then
    echo "Pulando re-flash. Script finalizado."
    exit 0
fi

# Verificar se já estamos em DFU mode
echo ""
echo "Verificando modo atual do dispositivo..."
if $BOSE_DFU info $FORCE_FLAG &>/dev/null; then
    echo "Dispositivo em modo NORMAL. Entrando em DFU mode..."
    echo ""

    $BOSE_DFU enter-dfu $FORCE_FLAG

    echo ""
    echo "✓ Comando enviado. Aguardando dispositivo reiniciar em DFU mode..."
    echo "  (Isso pode levar 5-10 segundos)"
    sleep 8

    echo ""
    echo "Verificando dispositivos após entrada em DFU:"
    $BOSE_DFU list
else
    echo "✓ Dispositivo já está em DFU mode"
fi

echo ""
echo "=============================================="
echo "ETAPA 5: Baixando Firmware"
echo "=============================================="
echo ""
echo "Opções de firmware:"
echo "  1. Usar firmware do repositório bosefirmware/ced (recomendado)"
echo "  2. Usar firmware de downloads.bose.com (oficial)"
echo "  3. Já tenho um arquivo .dfu"
echo ""

read -p "Escolha uma opção (1/2/3): " -n 1 -r
echo
echo ""

FIRMWARE_FILE=""

case $REPLY in
    1)
        echo "Clonando repositório de firmware não-oficial..."
        if [ ! -d "ced" ]; then
            git clone https://github.com/bosefirmware/ced.git
        else
            echo "✓ Repositório já existe"
        fi

        echo ""
        echo "Arquivos .dfu disponíveis:"
        find ced -name "*.dfu" -type f

        echo ""
        read -p "Digite o caminho do arquivo .dfu que deseja usar: " FIRMWARE_FILE
        ;;
    2)
        echo "Você precisará baixar manualmente de:"
        echo "  https://downloads.bose.com/"
        echo ""
        echo "Processo:"
        echo "  1. Verifique lookup.xml para encontrar seu dispositivo"
        echo "  2. Baixe o firmware .dfu apropriado"
        echo ""
        read -p "Digite o caminho do arquivo .dfu baixado: " FIRMWARE_FILE
        ;;
    3)
        read -p "Digite o caminho do arquivo .dfu: " FIRMWARE_FILE
        ;;
    *)
        echo "Opção inválida. Saindo."
        exit 1
        ;;
esac

if [ ! -f "$FIRMWARE_FILE" ]; then
    echo "❌ ERRO: Arquivo não encontrado: $FIRMWARE_FILE"
    exit 1
fi

echo ""
echo "=============================================="
echo "ETAPA 6: Analisando arquivo de firmware"
echo "=============================================="
$BOSE_DFU file-info "$FIRMWARE_FILE"
echo ""

read -p "O firmware acima parece correto? (s/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[SsYy]$ ]]; then
    echo "Re-flash cancelado."
    exit 1
fi

echo ""
echo "=============================================="
echo "ETAPA 7: INICIANDO RE-FLASH"
echo "=============================================="
echo ""
echo "⚠️⚠️⚠️  NÃO DESCONECTE O CABO  ⚠️⚠️⚠️"
echo ""

# Usar --wildcard-fw se o firmware tiver USB ID incompleto
$BOSE_DFU download $FORCE_FLAG --wildcard-fw "$FIRMWARE_FILE"

echo ""
echo "✓✓✓ Re-flash concluído com sucesso! ✓✓✓"
echo ""

echo "=============================================="
echo "ETAPA 8: Saindo do DFU mode"
echo "=============================================="
$BOSE_DFU leave-dfu $FORCE_FLAG

echo ""
echo "✓ Dispositivo reiniciando em modo normal..."
sleep 5

echo ""
echo "=============================================="
echo "FINALIZADO"
echo "=============================================="
echo ""
echo "O processo foi concluído. Seu QuietComfort Ultra deve:"
echo "  ✓ Reiniciar automaticamente"
echo "  ✓ Ter o DSP de áudio limpo/resetado"
echo "  ✓ Restaurar o som no canal direito"
echo ""
echo "Próximos passos:"
echo "  1. Aguarde o dispositivo reiniciar completamente"
echo "  2. Teste o áudio no canal direito"
echo "  3. Se necessário, parear novamente com dispositivos Bluetooth"
echo ""
echo "Se o problema persistir:"
echo "  - Tente um downgrade para firmware mais antigo"
echo "  - Execute novamente este script"
echo "  - Considere contato com suporte Bose (dano mecânico no botão)"
echo ""
echo "Boa sorte! 🎧"
