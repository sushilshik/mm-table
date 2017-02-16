# mm-table


##Setup mm-table:

1) dnf install sqlite ruby ruby-devel rubygem-nokogiri rubygem-gruff rubygem-sqlite3 rubygem-sinatra rubygem-json

2) gem install neo4j

3) Установка neo4j

  3.1 Скачать с https://neo4j.com/download/other-releases/ файл базы neo4j-community-2.\*-unix.tar.gz
  
  3.2 распаковать
  
  3.3 переименовать в neo4j
  
  3.4 скопировать в mm-table/
  
  3.5 в файле neo4j/conf/neo4j-server.properties параметру dbms.security.auth_enabled задайте значение false

4) Поместить файл VUE.jar в директорию mm-table



##Запуск mm-table:

1) ruby server.rb

2) Откройте в браузере http://localhost:4567/m - страница загружается около минуты


Чтобы в VUE можно было задавать координаты положения холста при загрузке файла, нужна сборка VUE с патчем.



##Патчим VUE

1) Скачиваем VUE

git clone https://github.com/VUE/VUE.git

2) Достаем тэг 3.2.2

git checkout tags/3.2.2

3) Создаем рабочую ветку

git checkout -b 3.2.2-work

4) Скачиваем патч 

http://nkbtr.org/down/coordinates_parameters.patch.zip

5) Распаковываем

unzip coordinates_parameters.patch.zip

6) Патчим

git apply coordinates_parameters.patch

7) Собираем

ant compile

ant jar

8) Итоговый файл в VUE/VUE2/src/build/

9) Запускаем для проверки: java -jar VUE.jar

10) копируем файл VUE.jar в mm-table/



##Связь:

http://sushilshik.livejournal.com/

http://www.facebook.com/mike.ahundov

http://vk.com/ahundov
