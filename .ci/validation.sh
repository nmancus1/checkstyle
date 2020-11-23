#!/bin/bash
set -e

removeFolderWithProtectedFiles() {
  find "$1" -delete
}

case $1 in

all-sevntu-checks)
  working_dir=.ci-temp/all-sevntu-checks
  mkdir -p $working_dir
  xmlstarlet sel --net --template -m .//module -v "@name" -n config/checkstyle_sevntu_checks.xml \
    | grep -vE "Checker|TreeWalker|Filter|Holder" | grep -v "^$" \
    | sed "s/com\.github\.sevntu\.checkstyle\.checks\..*\.//" \
    | sort | uniq | sed "s/Check$//" > $working_dir/file.txt
  wget -q http://sevntu-checkstyle.github.io/sevntu.checkstyle/apidocs/allclasses-frame.html -O - \
    | grep "<li>" | cut -d '>' -f 3 | sed "s/<\/a//" \
    | grep -E "Check$" \
    | sort | uniq | sed "s/Check$//" > $working_dir/web.txt
  # temporal ignore list
  # sed -i.backup '/Jsr305Annotations/d' web.txt
  diff -u $working_dir/web.txt $working_dir/file.txt
  removeFolderWithProtectedFiles $working_dir
  ;;

check-missing-pitests)
  fail=0
  mkdir -p target

  list=($(cat pom.xml | \
    xmlstarlet sel --ps -N pom="http://maven.apache.org/POM/4.0.0" \
    -t -v '//pom:profile[./pom:id[contains(text(),'pitest')]]//pom:targetClasses/pom:param'))

  #  Temporary skip for Metadata generator related files for
  #  https://github.com/checkstyle/checkstyle/issues/8761
  list=("com.puppycrawl.tools.checkstyle.meta.*" "${list[@]}")

  CMD="find src/main/java -type f ! -name 'package-info.java'"

  for item in "${list[@]}"
  do
    item=${item//\./\/}
    if [[ $item == */\*  ]] ; then
     item=$item
    else
      if [[ $item != *\* ]] ; then
        item="$item.java"
      else
        item="${item::-1}.java"
      fi
    fi

    CMD="$CMD -and ! -wholename '*/$item'"
  done

  CMD="$CMD | sort > target/result.txt"
  eval $CMD

  results=$(cat target/result.txt)

  echo "List of missing files in pitest profiles: $results"

  if [[ -n $results ]] ; then
    fail=1
  fi

  sleep 5s
  exit $fail
  ;;

eclipse-static-analysis)
  mvn -e clean compile exec:exec -Peclipse-compiler
  ;;

nondex)
  mvn -e --fail-never clean nondex:nondex -DargLine='-Xms1024m -Xmx2048m'
  mkdir -p .ci-temp
  cat `grep -RlE 'td class=.x' .nondex/ | cat` < /dev/null > .ci-temp/output.txt
  RESULT=$(cat .ci-temp/output.txt | wc -c)
  cat .ci-temp/output.txt
  echo 'Size of output:'$RESULT
  if [[ $RESULT != 0 ]]; then sleep 5s; false; fi
  rm .ci-temp/output.txt
  ;;

no-error-pmd)
  CS_POM_VERSION=$(mvn -e -q -Dexec.executable='echo' -Dexec.args='${project.version}' \
                     --non-recursive org.codehaus.mojo:exec-maven-plugin:1.3.1:exec)
  echo "CS_version: ${CS_POM_VERSION}"
  mkdir -p .ci-temp/
  cd .ci-temp/
  git clone https://github.com/pmd/pmd.git
  cd pmd
  mvn -e install checkstyle:check -Dcheckstyle.version=${CS_POM_VERSION}
  cd ..
  removeFolderWithProtectedFiles pmd
  ;;

no-violation-test-configurate)
  CS_POM_VERSION=$(mvn -e -q -Dexec.executable='echo' -Dexec.args='${project.version}' \
                     --non-recursive org.codehaus.mojo:exec-maven-plugin:1.6.0:exec)
  echo "CS_version: ${CS_POM_VERSION}"
  mkdir -p .ci-temp
  cd .ci-temp
  git clone https://github.com/SpongePowered/Configurate.git
  cd Configurate
  ./gradlew -PcheckstyleVersion="${CS_POM_VERSION}" -x test check
  cd ..
  removeFolderWithProtectedFiles Configurate
  ;;

no-violation-test-josm)
  CS_POM_VERSION=$(mvn -e -q -Dexec.executable='echo' -Dexec.args='${project.version}' \
                     --non-recursive org.codehaus.mojo:exec-maven-plugin:1.6.0:exec)
  echo "CS_version: ${CS_POM_VERSION}"
  mkdir -p .ci-temp
  cd .ci-temp
  TESTED=$(wget -q -O - https://josm.openstreetmap.de/wiki/TestedVersion?format=txt)
  echo "JOSM revision: ${TESTED}"
  svn -q --force export https://josm.openstreetmap.de/svn/trunk/ -r "${TESTED}" --native-eol LF josm
  cd josm
  sed -i -E "s/(name=\"checkstyle\" rev=\")([0-9]+\.[0-9]+(-SNAPSHOT)?)/\1${CS_POM_VERSION}/" \
   tools/ivy.xml
  ant -v checkstyle
  grep "<error" checkstyle-josm.xml | cat > errors.log
  echo "Checkstyle Errors:"
  RESULT=$(wc -l < errors.log)
  cat errors.log
  echo "Size of output: ${RESULT}"
  cd ..
  removeFolderWithProtectedFiles josm
  if [[ ${RESULT} != 0 ]]; then false; fi
  ;;

javac15)
  files=($(grep -Rl --include='*.java' ': Compilable with Java15' \
        src/test/resources-noncompilable || true))
  if [[  ${#files[@]} -eq 0 ]]; then
    echo "No Java15 files to process"
  else
    mkdir -p target
    for file in "${files[@]}"
    do
      javac --release 15 --enable-preview -d target "${file}"
    done
  fi
  ;;

*)
  echo "Unexpected argument: $1"
  sleep 5s
  false
  ;;

esac
