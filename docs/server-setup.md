\# Конфигурация виртуальной машины devops-vm



\## 1. Параметры машины



\- Гипервизор: VMware.

\- ОС: Ubuntu Server 24.04.5 LTS.

\- Оперативная память: около 2 ГБ, в free -h отображается 1,9 GiB.

\- Доступно 2 логических процессора.

\- Виртуальный диск sda: 25 ГБ.

\- Корневой логический том LVM: 11 ГБ.

\- Хостовая система: Windows.



\## 2. Сетевые интерфейсы



\- ens33: NAT, адрес 192.168.224.128/24; выход в интернет.

\- ens37: Host-only, адрес 192.168.142.129/24; связь с Windows.

\- Адрес Windows в сети Host-only: 192.168.142.1.

\- Адреса получаются по DHCP и могут измениться.



Файл /etc/netplan/60-host-only.yaml:



```yaml

network:

&#x20; version: 2

&#x20; ethernets:

&#x20;   ens37:

&#x20;     dhcp4: true

&#x20;     dhcp4-overrides:

&#x20;       use-routes: false

&#x20;       use-dns: false

&#x20;     optional: true

```



Применение и проверка:



```bash

sudo chmod 600 /etc/netplan/60-host-only.yaml

sudo netplan try

ip -brief address

```



\## 3. Правило проброса портов



Проброс портов не используется. Windows подключается напрямую

к адресу Host-only 192.168.142.129.



До усиления защиты SSH использовал порт 22, после — 2222.



\## 4. Учётные записи



\- student: исходный пользователь установки.

\- devops: административный пользователь, входит в группы devops, sudo, users.

\- Удалённый вход после усиления защиты разрешён только devops.

\- Аутентификация devops выполняется по ключу Ed25519.



Создание пользователя:



```bash

sudo adduser devops

sudo usermod -aG sudo devops

groups devops

```



В PowerShell Windows создаётся отдельный ключ:



```powershell

ssh-keygen -t ed25519 -C "devops-vm-key" -f "$env:USERPROFILE/.ssh/devops\_vm"

```



Закрытый ключ хранится только в Windows. Открытый ключ передаётся

до отключения парольного входа, когда SSH ещё работает на порту 22:



```powershell

Get-Content "$env:USERPROFILE/.ssh/devops\_vm.pub" | ssh devops@192.168.142.129 "mkdir -p \~/.ssh \&\& chmod 700 \~/.ssh \&\& cat >> \~/.ssh/authorized\_keys \&\& chmod 600 \~/.ssh/authorized\_keys"

```



Права на сервере:



\- /home/devops/.ssh: 700.

\- /home/devops/.ssh/authorized\_keys: 600.



Перед отключением паролей необходимо проверить вход по ключу.



\## 5. Служба SSH



Резервная копия основного файла:



```bash

sudo cp /etc/ssh/sshd\_config /etc/ssh/sshd\_config.backup

```



Файл /etc/ssh/sshd\_config.d/99-hardening.conf:



```text

Port 2222

PermitRootLogin no

PasswordAuthentication no

KbdInteractiveAuthentication no

PubkeyAuthentication yes

PermitEmptyPasswords no

MaxAuthTries 3

LoginGraceTime 30

AllowUsers devops

X11Forwarding no

ClientAliveInterval 300

ClientAliveCountMax 2

```



В файле /etc/ssh/sshd\_config.d/50-cloud-init.conf

закомментирована строка PasswordAuthentication yes.

Иначе её значение применяется раньше 99-hardening.conf.



Проверка и применение:



```bash

sudo sshd -t

sudo sshd -T

sudo systemctl disable --now ssh.socket

sudo systemctl enable --now ssh.service

sudo systemctl restart ssh

sudo ss -tlnp | grep sshd

```



Текущая SSH-сессия сохраняется до успешной проверки нового подключения.



Файл %USERPROFILE%\\.ssh\\config в Windows:



```text

Host devops

&#x20;   HostName 192.168.142.129

&#x20;   Port 2222

&#x20;   User devops

&#x20;   IdentityFile \~/.ssh/devops\_vm

&#x20;   IdentitiesOnly yes

```



Файл называется config без расширения .txt.

До смены порта сервера в клиентском файле используется Port 22.



Проверки из Windows:



```powershell

ssh devops

ssh -p 2222 root@192.168.142.129

ssh -o PubkeyAuthentication=no -o PasswordAuthentication=yes -o KbdInteractiveAuthentication=yes devops

```



Первое подключение успешно, два остальных отклоняются.



\## 6. Правила межсетевого экрана



Политики: deny incoming, allow outgoing.

SSH ограничен правилом LIMIT; HTTP и HTTPS разрешены.



Команды выполняются после перевода SSH на порт 2222.

Разрешение управляющего порта создаётся до включения UFW:



```bash

sudo ufw default deny incoming

sudo ufw default allow outgoing

sudo ufw limit 2222/tcp comment 'SSH rate-limited'

sudo ufw allow 80/tcp comment 'HTTP'

sudo ufw allow 443/tcp comment 'HTTPS'

sudo ufw enable

sudo ufw logging medium

sudo ufw status verbose

```



После включения проверяется новое подключение ssh devops.



Проверка блокировки из PowerShell Windows:



```powershell

curl.exe -m 3 http://192.168.142.129:8080

```



Просмотр журнала в Ubuntu:



```bash

sudo journalctl -k --since "5 min ago" --no-pager | grep 'UFW BLOCK'

```



В полученной записи:

SRC=192.168.142.1, DST=192.168.142.129, PROTO=TCP, DPT=8080.



\## 7. Снимки состояния



\- 01-clean-install: исходная установленная система и настроенная сеть.

\- 02-keys-configured: настроен вход devops по ключу.

\- 03-ssh-hardened: применено усиление защиты SSH.



Для восстановления после отката на 01-clean-install:

создать devops, передать открытый ключ, проверить вход,

настроить SSH, затем UFW и локальное имя.

Фактические адреса после отката проверяются через ip -brief address.



\## 8. Локальное имя



В Windows в файл C:\\Windows\\System32\\drivers\\etc\\hosts добавлено:



```text

192.168.142.129 devops.local

```



Проверки в Windows:



```powershell

ipconfig /flushdns

ping devops.local

ssh -p 2222 -i "$env:USERPROFILE/.ssh/devops\_vm" devops@devops.local

```



Настройка имени в Ubuntu:



```bash

sudo hostnamectl set-hostname devops-vm

```



Строка в /etc/hosts:



```text

127.0.1.1 devops-vm.devops.local devops-vm

```



Команда hostname -f возвращает devops-vm.devops.local.



\## 9. Аудит конфигурации



Скрипт: scripts/audit.sh. Запускается в Ubuntu.



На корректной конфигурации: PASS=6 FAIL=0, код возврата 0.

При временном MaxAuthTries 10: PASS=5 FAIL=1, код возврата 1.

После восстановления MaxAuthTries 3: PASS=6 FAIL=0, код 0.



Скрипт читает конфигурацию через sshd -T, поэтому для отрицательного

теста перезапуск SSH не выполнялся.

