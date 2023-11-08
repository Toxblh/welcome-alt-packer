#!/bin/bash

# Функция для выполнения команды с запросом пароля и ограничением на количество попыток
execute_with_retry() {
  local command="$1"
  local max_attempts=3
  local attempt_counter=0
  
  # Перечисляем возможные строки ошибок аутентификации на разных языках
  local auth_errors=("Authentication failure" "Аутентификация"
                     "authentification échouée" "Fehler bei der Authentifizierung"
                     "autenticación fallida")

  while [ $attempt_counter -lt $max_attempts ]; do
    ((attempt_counter++))
    error_output=$(su - -c "$command" 2>&1)
    retval=$?

    # Показ перехваченого вывода
    echo $error_output

    if [ $retval -eq 0 ]; then
      # Успех, выходим
      return 0
    else
      for error_msg in "${auth_errors[@]}"; do
        if [[ $error_output == *"$error_msg"* ]]; then
          echo "Неверный пароль, попытка $attempt_counter из $max_attempts."
          # Нашли совпадение, но команда не выполнена успешно, прервать эту while иттерацию

          if [ $attempt_counter -eq $max_attempts ]; then
            echo "Ошибка. Достигнут максимум попыток"
            return 1
          fi
          
          continue 2
        fi
      done

      # Если мы здесь, значит, ошибка не связана с аутентификацией, выходим
      return 0
    fi
  done
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

read -p $'Введите ваше имя и фамилию латиницей, например - \033[1;30mAnton Palgunov\033[0m: ' FULLNAME
read -p $'Введите ваш username, что часть email@altlinux.org, например - \033[1;30mtoxblh\033[0m: ' USERNAME

# Вопрос пользователю о необходимости установки sudo
read -p "Установить sudo в систему? (да/нет): " RESPONSE

if [[ "$RESPONSE" =~ ^([дД]|[yY]|[дД][аА]|[yY][eE][sS])$ ]]
then
    # Используем su для выполнения команды от имени рута
    echo ""
    echo "Введите пароль от root пользователя, для установки sudo"
    execute_with_retry 'control sudowheel:enabled'

else
    echo "Вы пропустили установку sudo."
fi

# Установка необходимых пакетов
echo ""
echo "Введите пароль от root пользователя, для установки необходимых для сборки пакетов"
if ! execute_with_retry "epm install -y etersoft-build-utils hasher faketime gear gear-sh-functions && \
            systemctl enable --now hasher-privd.service && \
            echo 'allowed_mountpoints=/proc' > /etc/hasher-priv/system && \
            hasher-useradd $SAVE_USER"; then
  echo "Команда не удалась после повторных попыток. Попробуйте ещё раз. Выход"
  exit 1
fi 

# Создание файла ~/.rpmmacros
cat << EOF > ~/.rpmmacros
%_topdir        %homedir/RPM
%_tmppath       %homedir/tmp
%_gpg_path      %homedir/.gnupg
%_gpg_name      ${FULLNAME} <${USERNAME}@altlinux.org>
%packager       ${FULLNAME} <${USERNAME}@altlinux.org>
EOF

cat ~/.rpmmacros

# Настройка hasher
mkdir ~/.hasher
cat << EOF > ~/.hasher/config
packager="${FULLNAME} <${USERNAME}@altlinux.org>"
known_mountpoints=/proc
EOF

cat ~/.hasher/config

# Конфигурация git
git config --global user.email ${USERNAME}@altlinux.org
git config --global user.name "${FULLNAME}"

cat ~/.gitconfig

# Добавление настроек в ~/.ssh/config
if ! grep -q "gitery.altlinux.org" ~/.ssh/config; then
cat << EOF >> ~/.ssh/config
 # Гитовница
   Host gitery
     HostName gitery.altlinux.org
     User alt_${USERNAME}
     Port 222

 # Сборочница
   Host gyle1
     HostName gyle.altlinux.org
     User alt_${USERNAME}
     Port 222
EOF
fi

cat ~/.ssh/config

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

\e[91mСреда настроена и готова к работе. Для использования hasher выйдите и зайдите в сессию.\e[39m"
