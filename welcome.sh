#!/bin/bash

# Функция для отображения прогресса
show_progress() {
    local message="$1"
    echo -e "\n\033[1;34m[INFO]\033[0m $message"
}

show_success() {
    local message="$1"
    echo -e "\033[1;32m[✓]\033[0m $message"
}

show_error() {
    local message="$1"
    echo -e "\033[1;31m[✗]\033[0m $message"
}

show_warning() {
    local message="$1"
    echo -e "\033[1;33m[!]\033[0m $message"
}

# Функции для проверки что уже настроено
is_sudo_configured() {
    # Проверяем наличие группы wheel в sudoers
    sudo -n true 2>/dev/null || grep -q "^%wheel" /etc/sudoers 2>/dev/null
}

is_packages_installed() {
    # Проверяем основные пакеты
    rpm -q etersoft-build-utils hasher gear >/dev/null 2>&1
}

# Функция для выполнения отдельной команды с описанием
execute_single_command() {
    local command="$1"
    local description="$2"
    local optional="$3"  # если "optional", то ошибка не критична
    
    echo ""
    show_progress "$description"
    showcmd "su" "-c" "$command"
    echo -e "\033[0;35mВводите пароль root:\033[0m"
    
    if su - -c "$command" 2>&1; then
        show_success "$description - выполнено"
        return 0
    else
        local exit_code=$?
        if [ "$optional" = "optional" ]; then
            show_warning "$description - пропущено (возможно уже настроено)"
            return 0
        else
            show_error "$description - ошибка (код: $exit_code)"
            return $exit_code
        fi
    fi
}

# Функция для проверки отдельных компонентов
check_package_installed() {
    rpm -q "$1" >/dev/null 2>&1
}

check_service_running() {
    systemctl is-active "$1" >/dev/null 2>&1
}

check_user_in_hasher() {
    groups "$1" 2>/dev/null | grep -q hasher
}

is_hasher_configured() {
    # Проверяем что пользователь в группе hasher и служба запущена
    check_user_in_hasher "$SAVE_USER" && check_service_running "hasher-privd.service"
}

is_rpmmacros_configured() {
    [ -f ~/.rpmmacros ] && grep -q "packager" ~/.rpmmacros
}

is_git_configured() {
    # Проверяем наличие файла конфигурации и что в нем есть altlinux.org
    if [ -f ~/.config/git/config-alt-team ] && grep -q "altlinux.org" ~/.gitconfig 2>/dev/null; then
        # Дополнительно проверяем, что GPG ключ настроен (не содержит <CHANGE_ME...>)
        if ! grep -q "<CHANGE_ME" ~/.config/git/config-alt-team 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

is_ssh_configured() {
    [ -f ~/.ssh/config ] && grep -q "gitery.altlinux.org" ~/.ssh/config
}

# Функции для работы с GPG
get_gpg_keys() {
    # Получаем список GPG ключей в формате: "ID Email Name"
    # Показываем только ключи, для которых есть секретный ключ (можно подписывать)
    gpg --list-secret-keys --with-colons 2>/dev/null | awk -F: '
    /^sec/ && $10 != "" { 
        keyid = $5
        userinfo = $10
        # Извлекаем email из userinfo
        if (match(userinfo, /<([^>]+)>/, email)) {
            print keyid " " email[1] " " userinfo
        }
    }'
}

# Функция для отображения команды в стиле etersoft-build-utils
showcmd()
{
    local i
    echo -e "\033[1;32m \$"
    for i in "$@" ; do
        echo -n " "
        # добавляем кавычки если есть пробелы
        echo -n "$i" | sed -e "s|\(.* .*\)|'\1'|g"
    done
    echo -e "\033[0m"
}

# Улучшенная функция для выполнения команды с запросом пароля
execute_with_retry() {
    local command="$1"
    local description="$2"
    local max_attempts=3
    local attempt_counter=0
    
    # Перечисляем возможные строки ошибок аутентификации на разных языках
    local auth_errors=("Authentication failure" "Аутентификация"
                       "authentification échouée" "Fehler bei der Authentifizierung"
                       "autenticación fallida" "su: Authentication failure"
                       "su: неверный пароль")

    show_progress "Выполняем: $description"
    echo ""
    echo -e "\033[1;37m📋 Команда для выполнения:\033[0m"
    showcmd "su" "-c" "$command"
    echo ""
    echo -e "\033[0;36m🔐 Требуется пароль root\033[0m"
    
    while [ $attempt_counter -lt $max_attempts ]; do
        ((attempt_counter++))
        
        if [ $attempt_counter -gt 1 ]; then
            echo ""
            show_warning "Попытка $attempt_counter из $max_attempts"
            echo -e "\033[0;33mВведите корректный пароль root или нажмите Ctrl+C для отмены\033[0m"
        fi
        
        # Создаем временный файл для захвата stderr (только для проверки ошибок аутентификации)
        local temp_error_file
        temp_error_file=$(mktemp)
        
        # Выполняем команду с real-time выводом
        echo -e "\033[0;35mВводите пароль (символы не отображаются):\033[0m"
        echo -e "\033[0;37m--- Вывод команды (real-time) ---\033[0m"
        
        # Выполняем команду с перенаправлением stderr в файл для анализа ошибок
        su - -c "$command" 2> >(tee "$temp_error_file" >&2)
        retval=$?
        
        echo -e "\033[0;37m--- Конец вывода ---\033[0m"
        
        # Читаем stderr для анализа ошибок аутентификации
        local error_output=""
        if [ -f "$temp_error_file" ]; then
            error_output=$(cat "$temp_error_file")
        fi
        
        # Показываем что команда завершена
        if [ $retval -eq 0 ]; then
            echo -e "\033[0;32m✓ Команда выполнена успешно\033[0m"
            rm -f "$temp_error_file"
            return 0
        else
            echo -e "\033[0;31m✗ Команда завершилась с ошибкой (код: $retval)\033[0m"
            
            # Проверяем, является ли ошибка проблемой аутентификации
            local is_auth_error=false
            for error_msg in "${auth_errors[@]}"; do
                if [[ $error_output == *"$error_msg"* ]]; then
                    is_auth_error=true
                    break
                fi
            done
            
            if [ "$is_auth_error" = true ]; then
                show_error "Неверный пароль!"
                
                if [ $attempt_counter -lt $max_attempts ]; then
                    echo -e "\033[0;33mОсталось попыток: $((max_attempts - attempt_counter))\033[0m"
                else
                    echo ""
                    show_error "Достигнуто максимальное количество попыток ввода пароля"
                    echo -e "\033[0;31mВозможные решения:\033[0m"
                    echo "  1. Убедитесь, что вы знаете пароль root"
                    echo "  2. Попробуйте запустить скрипт позже"
                    echo "  3. Обратитесь к системному администратору"
                    
                    read -p "Хотите попробовать еще раз? (да/нет): " retry_response
                    if [[ "$retry_response" =~ ^([дД]|[yY]|[дД][аА]|[yY][eE][sS])$ ]]; then
                        attempt_counter=0
                        max_attempts=3
                        rm -f "$temp_error_file"
                        continue
                    else
                        rm -f "$temp_error_file"
                        return 1
                    fi
                fi
            else
                # Ошибка не связана с аутентификацией
                show_error "Команда завершилась с ошибкой выполнения"
                
                echo ""
                read -p "Хотите попробовать выполнить команду еще раз? (да/нет): " retry_response
                if [[ "$retry_response" =~ ^([дД]|[yY]|[дД][аА]|[yY][eE][sS])$ ]]; then
                    attempt_counter=0
                    rm -f "$temp_error_file"
                    continue
                else
                    rm -f "$temp_error_file"
                    return $retval
                fi
            fi
        fi
        
        rm -f "$temp_error_file"
    done
    
    return 1
}

# Сохраняем юзерней пользователя для hasher
SAVE_USER=$USER

echo -e " __      __   _                      \033[1;33m_   _ _\033[0m     ___         _           "
echo -e " \ \    / /__| |__ ___ _ __  ___    \033[1;33m/_\ | | |_\033[0m  | _ \__ _ __| |_____ _ _ "
echo -e "  \ \/\/ / -_) / _/ _ \ '  \/ -_)  \033[1;33m/ _ \| |  _|\033[0m |  _/ _\` / _| / / -_) '_|"
echo -e "   \_/\_/\___|_\__\___/_|_|_\___| \033[1;33m/_/ \_\_|\__|\033[0m |_| \__,_\__|_\_\___|_|"
echo ""
echo -e "\033[1;37mДобро пожаловать в настройку среды для сборки пакетов Альт Linux\033[0m"
echo ""

# Интерактивный опросник
echo -e "\033[1;36m=== ПЕРСОНАЛЬНЫЕ НАСТРОЙКИ ===\033[0m"
echo "Для корректной работы с пакетами нужно настроить ваши данные."
echo ""

while true; do
    read -p $'Введите ваше имя и фамилию латиницей, например - \033[1;32mAnton Palgunov\033[0m: ' FULLNAME
    if [[ -n "$FULLNAME" && "$FULLNAME" =~ ^[a-zA-Z\ ]+$ ]]; then
        show_success "Имя принято: $FULLNAME"
        break
    else
        show_error "Имя должно содержать только латинские буквы и пробелы. Попробуйте еще раз."
    fi
done

while true; do
    read -p $'Введите ваш username (часть email@altlinux.org), например - \033[1;32mtoxblh\033[0m: ' USERNAME
    if [[ -n "$USERNAME" && "$USERNAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        show_success "Username принят: ${USERNAME}@altlinux.org"
        break
    else
        show_error "Username может содержать только латинские буквы, цифры, _ и -. Попробуйте еще раз."
    fi
done

# Вопрос пользователю о необходимости установки sudo
echo ""
echo -e "\033[1;36m=== НАСТРОЙКА SUDO ===\033[0m"

if is_sudo_configured; then
    show_success "Sudo уже настроен в системе"
    echo "Пользователи группы wheel могут использовать sudo."
else
    echo "Sudo позволяет выполнять команды от имени root без постоянного ввода пароля."
    echo -e "\033[0;37mБудет выполнена команда: \033[1;33mcontrol sudowheel enabled\033[0m"
    echo ""
    read -p "Установить sudo в систему? (да/нет): " RESPONSE

    if [[ "$RESPONSE" =~ ^([дД]|[yY]|[дД][аА]|[yY][eE][sS])$ ]]
    then
        echo ""
        if ! execute_single_command 'control sudowheel enabled' 'Настройка sudo для группы wheel'; then
            show_error "Не удалось настроить sudo. Продолжаем без sudo."
            echo "Вы можете настроить sudo позже вручную командой:"
            echo -e "  \033[0;33msu -c 'control sudowheel enabled'\033[0m"
        else
            show_success "Sudo успешно настроен!"
            echo "Теперь пользователи группы wheel могут использовать sudo."
        fi
    else
        show_warning "Установка sudo пропущена."
        echo "Для выполнения привилегированных команд потребуется пароль root."
    fi
fi

# Установка необходимых пакетов
echo ""
echo -e "\033[1;36m=== УСТАНОВКА ПАКЕТОВ ===\033[0m"

# Установка необходимых пакетов
echo ""
echo -e "\033[1;36m=== УСТАНОВКА ПАКЕТОВ ===\033[0m"

# Проверяем каждый компонент отдельно
echo "Проверяем состояние компонентов:"

# Проверка пакетов
PACKAGES_TO_INSTALL=""
for pkg in etersoft-build-utils hasher faketime gear gear-sh-functions; do
    if check_package_installed "$pkg"; then
        echo "  ✓ $pkg - установлен"
    else
        echo "  ✗ $pkg - требуется установка"
        PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL $pkg"
    fi
done

# Проверка службы hasher-privd
if check_service_running "hasher-privd.service"; then
    echo "  ✓ hasher-privd.service - запущена"
    SERVICE_NEEDS_START=false
else
    echo "  ✗ hasher-privd.service - требуется запуск"
    SERVICE_NEEDS_START=true
fi

# Проверка пользователя в группе hasher
if check_user_in_hasher "$SAVE_USER"; then
    echo "  ✓ Пользователь $SAVE_USER в группе hasher"
    USER_NEEDS_ADD=false
else
    echo "  ✗ Пользователь $SAVE_USER не в группе hasher"
    USER_NEEDS_ADD=true
fi

# Проверка конфигурации hasher-priv
if [ -f "/etc/hasher-priv/system" ] && grep -q "allowed_mountpoints=/proc" "/etc/hasher-priv/system"; then
    echo "  ✓ Конфигурация hasher-priv настроена"
    HASHER_CONFIG_NEEDED=false
else
    echo "  ✗ Конфигурация hasher-priv требует настройки"
    HASHER_CONFIG_NEEDED=true
fi

echo ""

# Если всё уже настроено
if [ -z "$PACKAGES_TO_INSTALL" ] && [ "$SERVICE_NEEDS_START" = false ] && [ "$USER_NEEDS_ADD" = false ] && [ "$HASHER_CONFIG_NEEDED" = false ]; then
    show_success "Все компоненты уже установлены и настроены"
    echo "  ✓ Все необходимые пакеты установлены"
    echo "  ✓ Служба hasher-privd запущена"
    echo "  ✓ Пользователь добавлен в группу hasher"
    echo "  ✓ Конфигурация hasher-priv настроена"
else
    echo "Выполняем установку и настройку..."
    echo ""
    
    # Устанавливаем пакеты
    if [ -n "$PACKAGES_TO_INSTALL" ]; then
        PACKAGES_TO_INSTALL=$(echo $PACKAGES_TO_INSTALL | sed 's/^ *//')  # убираем пробел в начале
        if ! execute_single_command "epm install -y$PACKAGES_TO_INSTALL" "Установка пакетов:$PACKAGES_TO_INSTALL"; then
            echo ""
            show_error "Не удалось установить пакеты!"
            echo "Попробуйте выполнить вручную:"
            echo -e "  \033[0;33msu -c 'epm install -y$PACKAGES_TO_INSTALL'\033[0m"
            
            read -p "Хотите продолжить настройку? (да/нет): " continue_response
            if [[ ! "$continue_response" =~ ^([дД]|[yY]|[дД][аА]|[yY][eE][sS])$ ]]; then
                echo "Выход из программы."
                exit 1
            fi
        fi
    fi
    
    # Настраиваем конфигурацию hasher-priv
    if [ "$HASHER_CONFIG_NEEDED" = true ]; then
        execute_single_command "echo 'allowed_mountpoints=/proc' > /etc/hasher-priv/system" "Настройка конфигурации hasher-priv" "optional"
    fi
    
    # Запускаем службу hasher-privd
    if [ "$SERVICE_NEEDS_START" = true ]; then
        execute_single_command "systemctl enable --now hasher-privd.service" "Запуск службы hasher-privd" "optional"
    fi
    
    # Добавляем пользователя в группу hasher
    if [ "$USER_NEEDS_ADD" = true ]; then
        execute_single_command "hasher-useradd $SAVE_USER" "Добавление пользователя $SAVE_USER в группу hasher" "optional"
    fi
    
    echo ""
    # Финальная проверка
    if check_package_installed "etersoft-build-utils" && check_service_running "hasher-privd.service" && check_user_in_hasher "$SAVE_USER"; then
        show_success "Все компоненты успешно установлены и настроены!"
    else
        show_warning "Настройка завершена, но некоторые компоненты могут требовать внимания"
        echo "Проверьте состояние после перезахода в сессию"
    fi
fi 

# Настройка RPM с правильным fingerprint
echo ""
echo -e "\033[1;36m=== НАСТРОЙКА RPM ===\033[0m"

if is_rpmmacros_configured; then
    show_success "Конфигурация RPM уже настроена"
    echo -e "\033[0;37m--- Текущий ~/.rpmmacros ---\033[0m"
    cat ~/.rpmmacros
    echo -e "\033[0;37m--- Конец файла ---\033[0m"
else
    show_progress "Создаем конфигурацию RPM в ~/.rpmmacros"

    # Получаем GPG fingerprint
    gpg_fingerprint=""
    if [ -f "$BACKUP_DIR/gpg_fingerprint.txt" ]; then
        gpg_fingerprint=$(cat "$BACKUP_DIR/gpg_fingerprint.txt")
    else
        # Пытаемся найти ключ автоматически
        existing_key=$(gpg --list-secret-keys --with-colons 2>/dev/null | grep -A5 "${USERNAME}@altlinux.org" | grep "^sec" | cut -d: -f5 | head -1)
        if [ -n "$existing_key" ]; then
            gpg_fingerprint=$(LANG=C gpg --fingerprint "$existing_key" | grep 'fingerprint =' | tr -d ' ' | cut -d= -f2)
        else
            gpg_fingerprint="<CHANGE_ME FROM \"gpg -k\">"
        fi
    fi

    cat << EOF > ~/.rpmmacros
%_topdir        %homedir/RPM
%_tmppath       %homedir/tmp
%_gpg_path      %homedir/.gnupg
%_gpg_name      $gpg_fingerprint
%packager       ${FULLNAME} <${USERNAME}@altlinux.org>
EOF

    show_success "Файл ~/.rpmmacros создан"
    echo -e "\033[0;37m--- Содержимое ~/.rpmmacros ---\033[0m"
    cat ~/.rpmmacros
    echo -e "\033[0;37m--- Конец файла ---\033[0m"
    
    if [[ "$gpg_fingerprint" == *"<CHANGE_ME"* ]]; then
        echo ""
        show_warning "GPG fingerprint не настроен"
        echo "После создания GPG ключа обновите %_gpg_name в ~/.rpmmacros"
    fi
fi

# Настройка hasher
echo ""
if [ -f ~/.hasher/config ] && grep -q "packager" ~/.hasher/config; then
    show_success "Конфигурация Hasher уже настроена"
    echo -e "\033[0;37m--- Текущий ~/.hasher/config ---\033[0m"
    cat ~/.hasher/config
    echo -e "\033[0;37m--- Конец файла ---\033[0m"
else
    show_progress "Создаем конфигурацию Hasher в ~/.hasher/config"
    mkdir -p ~/.hasher

    cat << EOF > ~/.hasher/config
packager="${FULLNAME} <${USERNAME}@altlinux.org>"
known_mountpoints=/proc
EOF

    show_success "Файл ~/.hasher/config создан"
    echo -e "\033[0;37m--- Содержимое ~/.hasher/config ---\033[0m"
    cat ~/.hasher/config
    echo -e "\033[0;37m--- Конец файла ---\033[0m"
fi

############
# Генерация ключей
############
echo ""
echo -e "\033[1;36m=== ГЕНЕРАЦИЯ КЛЮЧЕЙ ===\033[0m"

# Настройка рабочей директории
TEAM_DIR="$HOME/alt-team"
JOIN_DIR="$TEAM_DIR/join"
BACKUP_DIR="$TEAM_DIR/backup"
mkdir -p "$JOIN_DIR" "$BACKUP_DIR"

# Генерация SSH ключа
echo ""
echo -e "\033[1;35m--- SSH ключ ---\033[0m"
SSH_KEY_PATH="$HOME/.ssh/alt_team_ed25519"

if [ -f "$SSH_KEY_PATH" ]; then
    show_success "SSH ключ уже существует: $SSH_KEY_PATH"
    echo "Публичный ключ:"
    echo -e "\033[0;37m$(cat ${SSH_KEY_PATH}.pub)\033[0m"
    
    # Копируем публичный ключ в папку join
    cp "${SSH_KEY_PATH}.pub" "$JOIN_DIR/ssh_public_key.pub"
    show_success "Публичный SSH ключ скопирован в $JOIN_DIR/ssh_public_key.pub"
else
    show_progress "Генерируем SSH ключ ED25519 для ALT Team"
    echo "Создаем SSH ключ alt_team_ed25519 для работы с git-репозиториями ALT Linux"
    echo ""
    echo -e "\033[1;31m⚠️  ВАЖНО: SSH ключ ОБЯЗАТЕЛЬНО должен иметь пароль!\033[0m"
    echo -e "\033[0;33mПо требованиям ALT Linux Team все SSH ключи должны быть защищены паролем.\033[0m"
    echo ""
    echo -e "\033[1;33m📝 Сохраните пароль в менеджере паролей (например, Bitwarden)!\033[0m"
    echo -e "\033[0;31m❌ Восстановить пароль SSH ключа НЕВОЗМОЖНО!\033[0m"
    echo ""
    
    # Создаем SSH ключ с паролем
    if ssh-keygen -t ed25519 -C "${USERNAME}@altlinux.org" -f "$SSH_KEY_PATH"; then
        echo ""
        echo -e "\033[1;33m🔐 Проверка сохранения пароля\033[0m"
        echo "Для обеспечения безопасности подтвердите, что вы сохранили пароль SSH ключа."
        echo ""
        while true; do
            read -p "Вы сохранили пароль SSH ключа в надежном месте (менеджер паролей)? (да/нет): " password_saved
            if [[ "$password_saved" =~ ^([дД]|[yY]|[дД][аА]|[yY][eE][sS])$ ]]; then
                show_success "SSH ключ сгенерирован: $SSH_KEY_PATH"
                echo ""
                echo "Публичный ключ для загрузки на сервер:"
                echo -e "\033[1;32m$(cat ${SSH_KEY_PATH}.pub)\033[0m"
                
                # Копируем публичный ключ в папку join
                cp "${SSH_KEY_PATH}.pub" "$JOIN_DIR/ssh_public_key.pub"
                show_success "Публичный SSH ключ скопирован в $JOIN_DIR/ssh_public_key.pub"
                break
            else
                echo ""
                show_warning "Пожалуйста, сохраните пароль SSH ключа в безопасном месте!"
                echo "Без пароля вы не сможете использовать этот ключ."
                echo ""
            fi
        done
    else
        show_error "Не удалось создать SSH ключ"
    fi
fi

# Генерация GPG ключа  
echo ""
echo -e "\033[1;35m--- GPG ключ ---\033[0m"

# Проверяем есть ли уже GPG ключи с нашим email
existing_gpg_keys=$(gpg --list-secret-keys --with-colons 2>/dev/null | grep -A5 "${USERNAME}@altlinux.org" | grep "^sec" | cut -d: -f5)

if [ -n "$existing_gpg_keys" ]; then
    show_success "GPG ключ с email ${USERNAME}@altlinux.org уже существует"
    for key_id in $existing_gpg_keys; do
        echo "  Ключ: $key_id"
        # Экспортируем в файл
        gpg --armor --export "${USERNAME}@altlinux.org" > "$JOIN_DIR/gpg_public_key.asc"
        show_success "Публичный GPG ключ экспортирован в $JOIN_DIR/gpg_public_key.asc"
        
        # Получаем fingerprint для RPM конфигурации
        gpg_fingerprint=$(LANG=C gpg --fingerprint "$key_id" | grep 'fingerprint =' | tr -d ' ' | cut -d= -f2)
        echo "$gpg_fingerprint" > "$BACKUP_DIR/gpg_fingerprint.txt"
        break
    done
else
    show_progress "Автоматическое создание GPG ключа для ${USERNAME}@altlinux.org"
    echo "Создаем GPG ключ с рекомендуемыми параметрами ALT Linux..."
    echo ""
    echo "Параметры ключа:"
    echo "  - Тип: RSA and RSA"
    echo "  - Размер: 4096 бит"
    echo "  - Срок действия: без ограничений"
    echo "  - Имя: $FULLNAME"
    echo "  - Email: ${USERNAME}@altlinux.org"
    echo "  - Комментарий: (пустой)"
    echo ""
    
    # Создаем временный файл с параметрами GPG
    GPG_BATCH_FILE=$(mktemp)
    cat > "$GPG_BATCH_FILE" <<EOF
%echo Generating ALT Linux Team GPG key
Key-Type: RSA
Key-Length: 4096
Subkey-Type: RSA
Subkey-Length: 4096
Name-Real: $FULLNAME
Name-Email: ${USERNAME}@altlinux.org
Expire-Date: 0
%ask-passphrase
%commit
%echo done
EOF

    echo -e "\033[0;33mВведите пароль для защиты GPG ключа (рекомендуется):\033[0m"
    
    if gpg --batch --generate-key "$GPG_BATCH_FILE"; then
        rm -f "$GPG_BATCH_FILE"
        show_success "GPG ключ создан с рекомендуемыми параметрами"
        
        # Экспортируем публичный ключ
        gpg --armor --export "${USERNAME}@altlinux.org" > "$JOIN_DIR/gpg_public_key.asc"
        show_success "Публичный GPG ключ экспортирован в $JOIN_DIR/gpg_public_key.asc"
        
        # Получаем ID и fingerprint
        new_key_id=$(gpg --list-secret-keys --with-colons 2>/dev/null | grep -A5 "${USERNAME}@altlinux.org" | grep "^sec" | cut -d: -f5 | head -1)
        gpg_fingerprint=$(LANG=C gpg --fingerprint "$new_key_id" | grep 'fingerprint =' | tr -d ' ' | cut -d= -f2)
        echo "$gpg_fingerprint" > "$BACKUP_DIR/gpg_fingerprint.txt"
        
        echo ""
        echo "GPG ключ создан:"
        echo "  ID: $new_key_id"
        echo "  Fingerprint: $gpg_fingerprint"
    else
        rm -f "$GPG_BATCH_FILE"
        show_error "Не удалось создать GPG ключ"
        # Создаем заглушку
        echo "<CHANGE_ME FROM \"gpg -k\">" > "$BACKUP_DIR/gpg_fingerprint.txt"
    fi
fi

############
# Конфигурация git
############
echo ""
echo -e "\033[1;36m=== НАСТРОЙКА GIT ===\033[0m"
CONFIG_PATH="$HOME/.config/git/config-alt-team"

if is_git_configured; then
    show_success "Git уже настроен для ALT Team"
    echo -e "\033[0;33m[!] ВАЖНО:\033[0m Рабочая папка для проектов ALT: \033[1;32m$TEAM_DIR\033[0m"
    
    # Проверяем, какой GPG ключ настроен
    if [ -f "$CONFIG_PATH" ]; then
        current_key=$(grep "signingkey" "$CONFIG_PATH" 2>/dev/null | sed 's/.*signingkey = //' | tr -d ' ')
        if [ -n "$current_key" ] && [[ "$current_key" != *"<CHANGE_ME"* ]]; then
            # Проверяем, существует ли ключ в GPG
            if gpg --list-secret-keys "$current_key" >/dev/null 2>&1; then
                show_success "GPG ключ для подписи коммитов: $current_key ✓"
            else
                show_warning "GPG ключ $current_key не найден в keyring"
            fi
        else
            show_warning "GPG ключ для подписи коммитов не настроен"
            echo ""
            read -p "Хотите настроить GPG ключ для подписи коммитов? (да/нет): " setup_gpg_response
            if [[ "$setup_gpg_response" =~ ^([дД]|[yY]|[дД][аА]|[yY][eE][sS])$ ]]; then
                # Выбираем GPG ключ
                selected_key=$(select_gpg_key)
                
                # Обновляем конфигурацию
                if [[ "$selected_key" != *"<CHANGE_ME"* ]]; then
                    sed -i "s/signingkey = .*/signingkey = $selected_key/" "$CONFIG_PATH"
                    show_success "GPG ключ $selected_key обновлен в конфигурации git"
                else
                    show_warning "GPG ключ не выбран, конфигурация не изменена"
                fi
            fi
        fi
    fi
    
    echo ""
    echo -e "\033[0;37m--- Текущая конфигурация git Alt-team ($CONFIG_PATH) ---\033[0m"
    cat "$CONFIG_PATH"
    echo -e "\033[0;37m--- Конец файла ---\033[0m"
else
    show_progress "Создаем рабочую директорию: $TEAM_DIR"
    mkdir -p "$TEAM_DIR"

    show_progress "Создаем конфигурацию Git для ALT Team"
    mkdir -p "$(dirname "$CONFIG_PATH")"

    # Получаем GPG fingerprint для конфигурации
    echo ""
    gpg_fingerprint=""
    if [ -f "$BACKUP_DIR/gpg_fingerprint.txt" ]; then
        gpg_fingerprint=$(cat "$BACKUP_DIR/gpg_fingerprint.txt")
    else
        # Пытаемся найти ключ автоматически
        existing_key=$(gpg --list-secret-keys --with-colons 2>/dev/null | grep -A5 "${USERNAME}@altlinux.org" | grep "^sec" | cut -d: -f5 | head -1)
        if [ -n "$existing_key" ]; then
            gpg_fingerprint=$(LANG=C gpg --fingerprint "$existing_key" | grep 'fingerprint =' | tr -d ' ' | cut -d= -f2)
        else
            gpg_fingerprint="<CHANGE_ME FROM \"gpg -k\">"
        fi
    fi
    
    # Создаем конфигурацию git
    cat > "$CONFIG_PATH" <<EOF
[user]
    name = $FULLNAME
    email = ${USERNAME}@altlinux.org
    signingkey = $gpg_fingerprint

[gpg]
    format = openpgp

[commit]
    gpgsign = true
EOF

    show_success "Конфигурация Git создана: $CONFIG_PATH"
    
    # Если ключ не настроен, показываем предупреждение
    if [[ "$gpg_fingerprint" == *"<CHANGE_ME"* ]]; then
        echo ""
        show_warning "GPG ключ не настроен автоматически"
        echo "Для настройки подписи коммитов:"
        echo "  1. Создайте GPG ключ (если его нет): gpg --gen-key"
        echo "  2. Найдите fingerprint ключа: gpg --fingerprint"
        echo "  3. Отредактируйте файл: $CONFIG_PATH"
        echo "  4. Замените строку signingkey на ваш GPG fingerprint"
    else
        show_success "GPG fingerprint $gpg_fingerprint автоматически настроен для подписи коммитов"
    fi

    GITCONFIG="$HOME/.gitconfig"
    INCLUDE_BLOCK="[includeIf \"gitdir:${TEAM_DIR}/\"]"

    show_progress "Настраиваем условное подключение конфигурации"
    if ! grep -qF "$INCLUDE_BLOCK" "$GITCONFIG" 2>/dev/null; then
        echo "" >> "$GITCONFIG"
        echo "$INCLUDE_BLOCK" >> "$GITCONFIG"
        echo "    path = $CONFIG_PATH" >> "$GITCONFIG"
        show_success "Добавлен includeIf для $TEAM_DIR в ~/.gitconfig"
    else
        show_warning "includeIf для $TEAM_DIR уже есть в ~/.gitconfig"
    fi

    echo ""
    echo -e '\033[1;37m############\n# Git конфигурация\n############\033[0m'
    echo ""
    echo -e "\033[0;37m--- Основной gitconfig (~/.gitconfig) ---\033[0m"
    cat ~/.gitconfig

    echo ""
    echo -e "\033[0;37m--- Конфигурация git Alt-team ($CONFIG_PATH) ---\033[0m"
    cat $CONFIG_PATH

    echo ""
    echo -e "\033[0;33m[!] ВАЖНО:\033[0m Рабочая папка для проектов ALT: \033[1;32m$TEAM_DIR\033[0m"
fi

############
# Добавление настроек в ~/.ssh/config
############
echo ""
echo -e "\033[1;36m=== НАСТРОЙКА SSH ===\033[0m"

if is_ssh_configured; then
    show_success "SSH уже настроен для ALT серверов"
    echo ""
    echo -e "\033[0;37m--- Текущая SSH конфигурация (~/.ssh/config) ---\033[0m"
    cat ~/.ssh/config
    echo -e "\033[0;37m--- Конец файла ---\033[0m"
else
    show_progress "Настраиваем SSH конфигурацию для ALT серверов"

    # Создаем директорию .ssh если её нет
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh

    # Создаем файл config если его нет
    touch ~/.ssh/config
    chmod 600 ~/.ssh/config

    if ! grep -q "gitery.altlinux.org" ~/.ssh/config; then
cat << EOF >> ~/.ssh/config

# ALT Linux Team - используем alt_team_ed25519 ключ
Host gitery
    HostName gitery.altlinux.org
    User alt_${USERNAME}
    Port 222
    IdentityFile ~/.ssh/alt_team_ed25519

# Сборочница
Host gyle
    HostName gyle.altlinux.org
    User alt_${USERNAME}
    Port 222
    IdentityFile ~/.ssh/alt_team_ed25519
EOF
        show_success "SSH конфигурация добавлена"
    else
        show_warning "SSH конфигурация для ALT серверов уже существует"
    fi

    echo ""
    echo -e "\033[0;37m--- Текущая SSH конфигурация (~/.ssh/config) ---\033[0m"
    cat ~/.ssh/config
    echo -e "\033[0;37m--- Конец файла ---\033[0m"
fi

echo ""
echo -e "\033[1;36m=== СОЗДАНИЕ БЕКАПОВ И ИНСТРУКЦИЙ ===\033[0m"

show_progress "Создаем бекапы конфигурационных файлов"

# Копируем конфигурационные файлы в бекап
files_to_backup=(
    "$HOME/.rpmmacros:rpmmacros"
    "$HOME/.hasher/config:hasher_config"
    "$HOME/.config/git/config-alt-team:git_config_alt_team"
    "$HOME/.gitconfig:gitconfig"
    "$HOME/.ssh/config:ssh_config"
)

for file_pair in "${files_to_backup[@]}"; do
    src_file="${file_pair%:*}"
    dst_name="${file_pair#*:}"
    
    if [ -f "$src_file" ]; then
        cp "$src_file" "$BACKUP_DIR/$dst_name"
        show_success "Скопировано: $src_file → $BACKUP_DIR/$dst_name"
    fi
done

# Создаем файл с информацией о пользователе в backup
cat > "$BACKUP_DIR/user_info.txt" <<EOF
# Информация о пользователе ALT Linux
FULLNAME="$FULLNAME"
USERNAME="$USERNAME"
EMAIL="${USERNAME}@altlinux.org"
TEAM_DIR="$TEAM_DIR"
SETUP_DATE="$(date)"
EOF

# Создаем README с инструкциями в корневой папке team
cat > "$TEAM_DIR/README.md" <<'EOF'
# Настройка среды разработчика ALT Linux

Этот каталог содержит файлы для настройки среды разработки пакетов ALT Linux.

## Структура папок

### `join/` - Файлы для отправки
- `ssh_public_key.pub` - Публичный SSH ключ (загрузите на gitery.altlinux.org)
- `gpg_public_key.asc` - Публичный GPG ключ для проверки подписей

### `backup/` - Конфигурация и восстановление
- `gpg_fingerprint.txt` - Fingerprint GPG ключа для RPM конфигурации
- `user_info.txt` - Информация о пользователе
- `restore.sh` - Скрипт для восстановления на новой машине
- Бекапы конфигурационных файлов

## Восстановление на новой машине

1. Скопируйте эту папку на новую машину
2. Запустите скрипт восстановления:
   ```bash
   cd backup
   chmod +x restore.sh
   ./restore.sh
   ```
3. Скопируйте приватные ключи SSH и GPG вручную:
   - SSH: `~/.ssh/alt_team_ed25519` (приватный ключ)
   - GPG: экспорт/импорт приватного ключа
4. Перезайдите в сессию для применения настроек hasher

## Следующие шаги

1. **Загрузите SSH ключ на сервер**:
   - Откройте https://gitery.altlinux.org
   - Войдите в систему
   - Добавьте содержимое файла `join/ssh_public_key.pub` в настройки SSH ключей

2. **Отправьте GPG ключ координатору команды**:
   - Файл `gpg_public_key.asc` содержит ваш публичный GPG ключ
   - Отправьте его для добавления в keyring команды

3. **Начните работу с пакетами**:
   - Все проекты размещайте в `~/alt-team/`
   - Клонируйте репозитории: `git clone git://git.altlinux.org/gears/<package>.git`

## Полезные команды

### Основные команды для работы с пакетами
```bash
# Скачать пакет из Сизифа
rpmgp -g package_name

# Собрать пакет в системе
rpmbb

# Собрать пакет в hasher
rpmbsh

# Отправить пакет в Сизиф
rpmbs -u
```

### Работа с Git
```bash
# Клонировать пакет
git clone git://git.altlinux.org/gears/p/package_name.git

# Проверить подпись коммитов
git log --show-signature
```

### Проверка настройки
```bash
# Проверить GPG ключи
gpg --list-secret-keys

# Проверить SSH соединение
ssh -T git@gitery.altlinux.org

# Проверить hasher
hsh --version
```

## Полезные ссылки

- [Сборка пакетов start](https://www.altlinux.org/Сборка_пакетов_start) - Короткий и быстрый старт
- [ALT Packaging Guide](https://alt-packaging-guide.github.io) - Руководство о сборке пакетов
- [Etersoft-build-utils howto](https://www.altlinux.org/Etersoft-build-utils_howto) - Полное руководство по Этерсофт утилит

EOF

# Создаем скрипт восстановления в backup
cat > "$BACKUP_DIR/restore.sh" <<'EOF'
#!/bin/bash

# Скрипт восстановления конфигурации ALT Linux на новой машине

set -e

echo "🔄 Восстановление конфигурации среды разработчика ALT Linux"

# Проверяем что мы в правильной директории
if [ ! -f "user_info.txt" ]; then
    echo "❌ Файл user_info.txt не найден. Запустите скрипт из папки с бекапами."
    exit 1
fi

# Загружаем информацию о пользователе
source user_info.txt

echo "👤 Восстанавливаем конфигурацию для: $FULLNAME ($EMAIL)"

# Создаем необходимые директории
mkdir -p ~/.config/git
mkdir -p ~/.hasher
mkdir -p ~/.ssh
mkdir -p "$TEAM_DIR"

echo "📂 Директории созданы"

# Восстанавливаем файлы конфигурации
if [ -d "backup" ]; then
    echo "📋 Восстанавливаем конфигурационные файлы..."
    
    [ -f "backup/rpmmacros" ] && cp backup/rpmmacros ~/.rpmmacros && echo "  ✓ ~/.rpmmacros"
    [ -f "backup/hasher_config" ] && cp backup/hasher_config ~/.hasher/config && echo "  ✓ ~/.hasher/config"
    [ -f "backup/git_config_alt_team" ] && cp backup/git_config_alt_team ~/.config/git/config-alt-team && echo "  ✓ ~/.config/git/config-alt-team"
    [ -f "backup/ssh_config" ] && cp backup/ssh_config ~/.ssh/config && echo "  ✓ ~/.ssh/config"
    
    # Восстанавливаем gitconfig с includeIf
    if [ -f "backup/gitconfig" ]; then
        if ! grep -q "includeIf.*$TEAM_DIR" ~/.gitconfig 2>/dev/null; then
            echo "" >> ~/.gitconfig
            echo "[includeIf \"gitdir:$TEAM_DIR/\"]" >> ~/.gitconfig
            echo "    path = ~/.config/git/config-alt-team" >> ~/.gitconfig
            echo "  ✓ ~/.gitconfig (добавлен includeIf)"
        else
            echo "  ✓ ~/.gitconfig (includeIf уже настроен)"
        fi
    fi
fi

# Устанавливаем правильные права доступа
chmod 600 ~/.ssh/config 2>/dev/null || true
chmod 700 ~/.ssh 2>/dev/null || true
chmod 700 ~/.hasher 2>/dev/null || true

echo "🔐 Права доступа установлены"

echo ""
echo "✅ Конфигурация восстановлена!"
echo ""
echo "🔑 ВАЖНЫЕ СЛЕДУЮЩИЕ ШАГИ:"
echo "1. Скопируйте приватный SSH ключ в ~/.ssh/alt_team_ed25519"
echo "2. Импортируйте приватный GPG ключ: gpg --import private_key.asc"
echo "3. Выйдите и зайдите в сессию заново для применения настроек hasher"
echo ""
echo "📁 Рабочая папка для проектов ALT: $TEAM_DIR"
EOF

chmod +x "$BACKUP_DIR/restore.sh"

show_success "Создана структура папок в $TEAM_DIR:"
echo "  📁 join/ - файлы для отправки (публичные ключи)"
echo "  📁 backup/ - конфигурация и скрипт восстановления"
echo "  📄 README.md - инструкции по использованию"

echo ""
echo -e "\033[1;36m=== НАСТРОЙКА ЗАВЕРШЕНА ===\033[0m"
echo ""

echo -e "\e[96mTL;DR полезных команд\e[39m

\e[93m## Загрузить пакет ##\e[39m

- Проверка наличия пакета в Сизифе
    \e[92mrpmgp -c название_пакета\e[39m

- Загрузка уже собранного в Сизиф пакета
    \e[92mrpmgp -g neofetch\e[39m

\e[93m## Сборка в системе ##\e[39m

- Собрать пакет в системе
    \e[92mrpmbb\e[39m

- Отладить только шаг установки файлов
    \e[92mrpmbb -i\e[39m

- Отладить только шаг упаковки пакета
    \e[92mrpmbb -p\e[39m

\e[93m## Сборка в Hasher ##\e[39m

- Собрать пакет в hasher
    \e[92mrpmbsh\e[39m

- Собрать и установить '-i' внутри и отправить '-u' в Сизиф
    \e[92mrpmbsh -i\e[39m

\e[93m## Отправка пакета ##\e[39m

- Отправить пакет на сборку в Сизиф
    \e[92mrpmbs -u\e[39m

\e[93m## Обновление пакета ##\e[39m

- Обновление исходников, если в Source указан URL к файлу с исходниками:
        - # Source-url: http://example.com/%name/%name-%version.zip
        - # Source-git: http://github.com/user/repo.git

    \e[92mrpmgs [-f] %новая версия, как в тегах%\e[39m

- Автоматическое обновление, скачает обновление, соберёт, запустит тест и после отправит в Сизиф
    \e[92mrpmrb новая_версия\e[39m

Полезные ссылки: 
- \e[94mhttps://www.altlinux.org/Сборка_пакетов_(etersoft-build-utils)\e[39m -  Короткий и быстрый старт
- \e[94mhttps://alt-packaging-guide.github.io\e[39m - Руководство о сборке пакетов
- \e[94mhttps://www.altlinux.org/Etersoft-build-utils_howto\e[39m - Полное руководство по Этерсофт утилит

\e[32m✓ Среда настроена и готова к работе!\e[39m

\e[91m🔑 ВАЖНЫЕ СЛЕДУЮЩИЕ ШАГИ:\e[39m
1. \e[93mВыйдите и зайдите в сессию заново\e[39m для применения настроек hasher
2. \e[93mЗагрузите SSH ключ на gitery.altlinux.org\e[39m:
   - Публичный ключ: \e[1;32m$JOIN_DIR/ssh_public_key.pub\e[39m
3. \e[93mОтправьте GPG ключ координатору команды\e[39m:
   - Публичный ключ: \e[1;32m$JOIN_DIR/gpg_public_key.asc\e[39m

\e[96m📦 ВАЖНАЯ СТРУКТУРА ДЛЯ СОХРАНЕНИЯ:\e[39m
\e[1;33m$TEAM_DIR\e[39m
├── join/ - файлы для отправки (публичные ключи)
├── backup/ - конфигурация и скрипт восстановления
└── README.md - инструкции
Скопируйте эту папку в надежное место!

\e[36mВсе проекты ALT размещайте в директории:\e[39m \e[1;32m$TEAM_DIR\e[39m"

echo ""
show_success "Настройка успешно завершена! Добро пожаловать в команду ALT Linux!"
