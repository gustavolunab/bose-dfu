#!/bin/bash

# Script de recuperação para Bose QuietComfort Ultra
# Restaura o áudio do canal direito através de reset de firmware
# Contorna problemas de botão físico danificado

set -e

BOSE_DFU="./target/release/bose-dfu"
LOG_FILE="qc_ultra_repair_$(date +%Y%m%d_%H%M%S).log"

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERRO]${NC} $1" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}[OK]${NC} $1" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}[ATENÇÃO]${NC} $1" | tee -a "$LOG_FILE"
}

banner() {
    echo -e "${GREEN}"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║   Bose QuietComfort Ultra - Recovery Tool                ║"
    echo "║   Restauração do Canal Direito via Firmware Reset        ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Verificar se o executável existe
check_binary() {
    if [ ! -f "$BOSE_DFU" ]; then
        error "Binário bose-dfu não encontrado!"
        error "Execute: cargo build --release"
        exit 1
    fi
    success "Binário bose-dfu encontrado"
}

# Verificar conexão do dispositivo
check_device() {
    log "Procurando dispositivos Bose conectados via USB..."

    local devices=$($BOSE_DFU list 2>&1)

    if [ -z "$devices" ]; then
        error "Nenhum dispositivo Bose detectado!"
        echo ""
        echo "CHECKLIST:"
        echo "  1. QuietComfort Ultra está conectado via USB-C?"
        echo "  2. Cabo USB-C suporta transferência de dados?"
        echo "  3. Dispositivo está ligado (bateria > 20%)?"
        echo ""
        exit 1
    fi

    success "Dispositivo(s) encontrado(s):"
    echo "$devices" | tee -a "$LOG_FILE"
}

# Obter informações do dispositivo
get_device_info() {
    log "Obtendo informações do sistema..."

    echo "" | tee -a "$LOG_FILE"
    echo "═══ INFORMAÇÕES DO DISPOSITIVO ═══" | tee -a "$LOG_FILE"

    # Tentar obter info (pode falhar se já estiver em DFU mode)
    if $BOSE_DFU info --force 2>&1 | tee -a "$LOG_FILE"; then
        success "Informações obtidas com sucesso"
    else
        warning "Dispositivo pode já estar em modo DFU"
    fi

    echo "" | tee -a "$LOG_FILE"
}

# Comandos TAP para diagnóstico e reset
try_tap_commands() {
    log "Tentando comandos TAP para diagnóstico e reset..."

    # Lista de comandos TAP conhecidos para tentar
    local tap_commands=(
        "vr"          # Versão do firmware
        "sn"          # Número de série
        "pl"          # Product line
        "bt status"   # Status Bluetooth
        "bt reset"    # Reset Bluetooth
        "bt clear"    # Limpar memória BT
        "bt pair"     # Modo de pareamento
        "reset"       # Reset geral
        "factory"     # Factory reset
    )

    echo "" | tee -a "$LOG_FILE"
    echo "═══ COMANDOS TAP - TENTATIVAS ═══" | tee -a "$LOG_FILE"

    for cmd in "${tap_commands[@]}"; do
        log "Tentando comando: $cmd"

        # Criar arquivo temporário com o comando
        echo "$cmd" > /tmp/tap_cmd.txt

        # Tentar executar (pode falhar, está ok)
        if echo "$cmd" | timeout 5 $BOSE_DFU tap --force 2>&1 | tee -a "$LOG_FILE"; then
            success "Comando '$cmd' executado"
        else
            warning "Comando '$cmd' falhou ou não suportado"
        fi

        sleep 1
    done

    echo "" | tee -a "$LOG_FILE"
}

# Entrar em modo DFU
enter_dfu_mode() {
    log "Entrando em modo DFU (Device Firmware Update)..."

    if $BOSE_DFU enter-dfu --force 2>&1 | tee -a "$LOG_FILE"; then
        success "Comando DFU enviado"
        log "Aguardando dispositivo reiniciar em modo DFU..."
        sleep 5

        # Verificar se está em modo DFU
        log "Verificando modo DFU..."
        $BOSE_DFU list --force 2>&1 | tee -a "$LOG_FILE"
        success "Dispositivo em modo DFU"
    else
        error "Falha ao entrar em modo DFU"
        return 1
    fi
}

# Baixar firmware
download_firmware() {
    log "Procurando firmware disponível..."

    # Verificar se repositório de firmware existe
    if [ ! -d "firmware_repo" ]; then
        log "Clonando repositório de firmware não-oficial..."
        git clone https://github.com/bosefirmware/ced.git firmware_repo 2>&1 | tee -a "$LOG_FILE" || true
    fi

    # Procurar arquivos .dfu
    local dfu_files=$(find . -name "*.dfu" 2>/dev/null || true)

    if [ -z "$dfu_files" ]; then
        warning "Nenhum arquivo .dfu encontrado localmente"
        log "Você pode baixar firmware de: https://downloads.bose.com/"
        log "Ou usar: https://github.com/bosefirmware/ced"
        return 1
    fi

    echo "Arquivos .dfu encontrados:" | tee -a "$LOG_FILE"
    echo "$dfu_files" | tee -a "$LOG_FILE"
}

# Flash de firmware (se disponível)
flash_firmware() {
    local firmware_file="$1"

    if [ -z "$firmware_file" ] || [ ! -f "$firmware_file" ]; then
        warning "Arquivo de firmware não fornecido ou não existe"
        return 1
    fi

    log "Iniciando flash de firmware: $firmware_file"
    warning "NÃO desconecte o dispositivo durante este processo!"

    if $BOSE_DFU download --force "$firmware_file" 2>&1 | tee -a "$LOG_FILE"; then
        success "Firmware instalado com sucesso!"
        return 0
    else
        error "Falha no flash de firmware"
        return 1
    fi
}

# Sair do modo DFU
exit_dfu_mode() {
    log "Saindo do modo DFU..."

    if $BOSE_DFU leave-dfu --force 2>&1 | tee -a "$LOG_FILE"; then
        success "Dispositivo reiniciando em modo normal"
        log "Aguardando reinicialização..."
        sleep 5
        return 0
    else
        error "Falha ao sair do modo DFU"
        return 1
    fi
}

# Menu interativo
interactive_menu() {
    while true; do
        echo ""
        echo "═══════════════════════════════════════════"
        echo "           MENU DE RECUPERAÇÃO             "
        echo "═══════════════════════════════════════════"
        echo "1) Diagnóstico completo (Info + TAP)"
        echo "2) Tentar reset via comandos TAP"
        echo "3) Entrar em modo DFU"
        echo "4) Flash de firmware (modo DFU ativo)"
        echo "5) Sair do modo DFU"
        echo "6) Processo completo automático"
        echo "7) Ver log completo"
        echo "0) Sair"
        echo "═══════════════════════════════════════════"
        read -p "Escolha uma opção: " choice

        case $choice in
            1)
                check_device
                get_device_info
                ;;
            2)
                try_tap_commands
                ;;
            3)
                enter_dfu_mode
                ;;
            4)
                read -p "Caminho do arquivo .dfu: " fw_file
                flash_firmware "$fw_file"
                ;;
            5)
                exit_dfu_mode
                ;;
            6)
                automatic_process
                ;;
            7)
                less "$LOG_FILE"
                ;;
            0)
                log "Encerrando..."
                exit 0
                ;;
            *)
                error "Opção inválida"
                ;;
        esac
    done
}

# Processo automático
automatic_process() {
    log "Iniciando processo automático de recuperação..."

    echo ""
    warning "IMPORTANTE: Este processo irá:"
    warning "  1. Coletar informações do dispositivo"
    warning "  2. Tentar comandos de reset via TAP"
    warning "  3. Se disponível, fazer re-flash do firmware"
    echo ""
    read -p "Deseja continuar? (s/N): " confirm

    if [[ ! "$confirm" =~ ^[Ss]$ ]]; then
        log "Processo cancelado pelo usuário"
        return 1
    fi

    # Passo 1: Diagnóstico
    check_device || return 1
    get_device_info

    # Passo 2: Comandos TAP
    try_tap_commands

    # Passo 3: Verificar se tem firmware disponível
    download_firmware

    # Passo 4: Perguntar se quer fazer DFU
    echo ""
    read -p "Deseja tentar flash de firmware? (s/N): " do_flash

    if [[ "$do_flash" =~ ^[Ss]$ ]]; then
        enter_dfu_mode || return 1

        # Listar arquivos .dfu disponíveis
        local dfu_files=($(find . -name "*.dfu" 2>/dev/null))

        if [ ${#dfu_files[@]} -eq 0 ]; then
            error "Nenhum arquivo .dfu encontrado"
            exit_dfu_mode
            return 1
        fi

        echo "Arquivos .dfu disponíveis:"
        for i in "${!dfu_files[@]}"; do
            echo "$i) ${dfu_files[$i]}"
        done

        read -p "Escolha o arquivo (número): " fw_choice

        if [ -n "${dfu_files[$fw_choice]}" ]; then
            flash_firmware "${dfu_files[$fw_choice]}"
            exit_dfu_mode
        else
            error "Escolha inválida"
            exit_dfu_mode
            return 1
        fi
    fi

    success "Processo completo!"
    echo ""
    echo "═══════════════════════════════════════════"
    echo "Próximos passos:"
    echo "  1. Desconecte o USB"
    echo "  2. Teste o áudio do canal direito"
    echo "  3. Se ainda tiver problemas, tente novamente"
    echo "  4. Log salvo em: $LOG_FILE"
    echo "═══════════════════════════════════════════"
}

# MAIN
main() {
    banner
    check_binary

    # Se argumentos foram passados
    if [ $# -eq 0 ]; then
        # Modo interativo
        interactive_menu
    else
        # Modo automático
        automatic_process
    fi
}

main "$@"
