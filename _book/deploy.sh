#!/usr/bin/env bash
# Set the English locale for the `date` command.
export LC_TIME=en_US.UTF-8
# GitHub username.
USERNAME=oubindo
# Name of the branch containing the Hugo source files.
SOURCE=gitbook
# The commit message.
MESSAGE="Gitbook rebuild $(date)"
## -------------------------------------------
msg() {
    printf "\033[1;32m :: %s\n\033[0m" "$1"
}
## -------------------------------------------
## -------------------------------------------
## 切换到 master
git checkout master
msg "Pulling down from ${SOURCE}<master>"
#从github更新原文件并生成静态页面
# git pull
## 使用 R 制作 md
Rscript -e 'blogdown::build_dir(dir = ".", force = FALSE, ignore = "[.]Rproj$")'  2>&1 >/dev/null
msg "Rebuild gitbook"
## 安装插件
# gitbook install ./
## 建立静态网页
/usr/local/bin/gitbook  build
git add -A 
git commit -m "update master"
git push origin master
## -------------------------------------------
## -------------------------------------------
msg "Pushing new info to gh-pages"
## 创建分支
# git checkout -b gh-pages
git checkout gh-pages
## 同步 master 的 _book 到 gh-pages
git checkout master -- _book
cp -r _book/* . 
echo "node_modules
_book">.gitignore
git add -A 
git commit -m "update gh-pages"
git push origin gh-pages
git checkout master
msg "We've happily done."
