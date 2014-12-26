#!/bin/bash


mapfile -t files < <(ls -1 010templates/*)

msgs=()
while IFS= read -r aline; do msgs+=("${aline}") ; done < gitlog

for i in `seq 0 $(( ${#files[*]} - 1 ))`; do
  printf "%-50s | %s\n" "${files[i]}" "${msgs[i]}"
done

# create initial commit
cd /tmp
rm -fr 010Templates 010templates
cp -r 010Templates-orig 010Templates
cp -r 010templates-orig 010templates
#git clone git+ssh://git@github.com/joshuadugie/010Templates.git
cp README.md 010Templates/
cd 010Templates
export GIT_AUTHOR_DATE="2003-09-01T00:00:00+0000"
export GIT_COMMITTER_DATE=${GIT_AUTHOR_DATE}
git add .
git commit -m"Add README.md"
#git log --pretty=fuller
cd ..

# setup archive
mkdir /tmp/010Templates/archive
cp README.md.archive /tmp/010Templates/archive/README.md
cp /tmp/UNLICENSE /tmp/010Templates/archive/

for i in `seq 0 $(( ${#files[*]} - 1 ))`; do
  f="${files[i]}"
  d=${f:13:14}
  w=${f#010templates/${d}.}
  fd=${d:0:4}-${d:4:2}-${d:6:2}T${d:8:2}:${d:10:2}:${d:12:2}+0000
  export GIT_AUTHOR_DATE=${fd}
  export GIT_COMMITTER_DATE=${GIT_AUTHOR_DATE}
  cp "${f}" 010Templates/archive/${w}
  cd 010Templates/archive
  git add .
  git commit -m"${msgs[i]}"
  cd ../..
done

#git remote add origin git@github.com:joshuadugie/010Templates.git
#git push -u origin master
