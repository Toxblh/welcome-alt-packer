#!/bin/bash

# Вопрос пользователю о необходимости установки sudo
read -p "Установить sudo в систему? (да/нет): " RESPONSE

if [[ "$RESPONSE" =~ ^([дД]|[yY]|[дД][аА]|[yY][eE][sS])$ ]]
then
    # Используем su для выполнения команды от имени рута
    echo "Введите пароль от root пользователя, для установки sudo"
    su - -c 'control sudowheel:enabled'

else
    echo "Вы пропустили установку sudo."
fi

# Установка необходимых пакетов
echo "Введите пароль от root пользователя, для установки необходимых для сборки пакетов"
su - -c 'epm install etersoft-build-utils'

# Интерактивный опросник
read -p "Введите ваше имя и фамилию латиницей, например - Anton Palgunov: " FULLNAME
read -p "Введите ваш username, что часть email@altlinux.org, например - toxblh: " USERNAME

# Создание файла ~/.rpmmacros
cat << EOF > ~/.rpmmacros
%_topdir        %homedir/RPM
%_tmppath       %homedir/tmp
%_gpg_path      %homedir/.gnupg
%_gpg_name      ${FULLNAME} <${USERNAME}@altlinux.org>
%packager       ${FULLNAME} <${USERNAME}@altlinux.org>
EOF

cat ~/.rpmmacros

# Конфигурация git
git config --global user.email ${USERNAME}@altlinux.org
git config --global user.name "${FULLNAME}"

cat ~/.gitconfig

# Добавление настроек в ~/.ssh/config
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

cat ~/.ssh/config