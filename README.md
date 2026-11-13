# Hola Mundo en AWS ECS

Aplicación HTTP en Java 21 compilada con Maven dentro de Docker. GitHub Actions
crea el repositorio de imágenes en Amazon ECR, publica la imagen y ejecuta
Terraform para desplegarla como servicio en Amazon ECS con AWS Fargate.

| Ruta | Respuesta |
| --- | --- |
| `GET /` | `Hola mundo desde AWS ECS` |
| `GET /health` | `OK` |
| `GET /version` | SHA del commit desplegado |

## 1. Crea el repositorio en GitHub

En la página principal de GitHub, pulsa **+ → New repository**. Usa el nombre
`reto-java-ecs`, elige la visibilidad acordada con el evaluador y marca
**Add README**. Confirma que la rama inicial sea `main`. En Windows, puedes
usar **Code → Open with GitHub Desktop** para clonarlo. Deja la carpeta clonada
lista para copiar el proyecto en el paso 4.

[Crear un repositorio](https://docs.github.com/es/repositories/creating-and-managing-repositories/creating-a-new-repository) · [Clonar con GitHub Desktop](https://docs.github.com/es/desktop/adding-and-cloning-repositories/cloning-a-repository-from-github-to-github-desktop)

## 2. Prepara AWS desde CloudShell

En la consola del proyecto de AWS, abre **CloudShell** y consulta la cuenta y la
región que vas a usar. Si te dieron una sandbox específica, usa esa cuenta y la
región habilitada para el reto.

```bash
aws sts get-caller-identity --query Account --output text
aws configure list
```

En CloudShell, elige **Actions → Upload file** y sube `Reto_Java_ECS.zip`.
Ejecuta estos comandos en CloudShell.

```bash
unzip -o ~/Reto_Java_ECS.zip -d ~/reto-java-ecs-setup
cd ~/reto-java-ecs-setup/reto-java-ecs
bash bootstrap.sh
```

El script crea un bucket S3 privado y versionado para el estado de Terraform.
Crea el rol de ejecución de ECS, el rol de despliegue y el usuario
programático `reto-java-ecs-ci`. Ese usuario solo puede asumir el rol de
despliegue. El rol de ECS descarga la imagen y envía los logs a CloudWatch.
El script imprime los nombres y valores de cuatro variables. Puedes preparar
GitHub durante los 15 minutos que AWS recomienda esperar tras habilitar
el versionado del bucket.

En la experiencia de proyectos de AWS, las políticas administradas de los
planes Free y Paid pueden bloquear la creación de proveedores IAM OIDC. La
ruta de arriba usa un usuario IAM dedicado para funcionar con ese tipo de
proyecto. Si recibes `AccessDenied` en `bootstrap.sh`, revisa la sección de
sandbox administrada.

[Subir archivos a CloudShell](https://docs.aws.amazon.com/cloudshell/latest/userguide/multiple-files-upload-download.html) · [Versionado de S3](https://docs.aws.amazon.com/es_es/AmazonS3/latest/userguide/manage-versioning-examples.html) · [Políticas de proyectos de AWS](https://docs.aws.amazon.com/accounts/latest/reference/scps-and-rcps-for-projects.html)

## 3. Conecta GitHub Actions con AWS

En AWS busca **IAM → Users → reto-java-ecs-ci → Security credentials → Create
access key**. Selecciona el caso de uso para una aplicación que se ejecuta
fuera de AWS y crea la clave. AWS muestra el secreto al momento de crearlo.

En el repositorio, abre **Settings → Secrets and variables → Actions**.
En **Variables**, pulsa **New repository variable** para cada valor que
imprimió `bootstrap.sh`. En **Secrets**, usa **New repository secret** para
guardar las dos credenciales de IAM. Guarda los valores de acceso únicamente
en GitHub Secrets.

| Pestaña | Nombre | Valor |
| --- | --- | --- |
| Variables | `AWS_REGION` | Región devuelta por el script |
| Variables | `TF_STATE_BUCKET` | Nombre del bucket S3 devuelto por el script |
| Variables | `AWS_DEPLOY_ROLE_ARN` | ARN de `reto-java-ecs-deploy` |
| Variables | `AWS_TASK_EXECUTION_ROLE_ARN` | ARN de `reto-java-ecs-execution` |
| Secrets | `AWS_ACCESS_KEY_ID` | Access key ID del usuario `reto-java-ecs-ci` |
| Secrets | `AWS_SECRET_ACCESS_KEY` | Secret access key de ese usuario |

[Claves de acceso de IAM](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_access-keys.html) · [Variables de GitHub Actions](https://docs.github.com/es/actions/how-tos/write-workflows/choose-what-workflows-do/use-variables) · [Secretos de GitHub Actions](https://docs.github.com/es/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets)

### Si usas una sandbox administrada con permisos limitados

Si IAM impide crear usuarios o roles, usa las credenciales temporales que te
proporciona el laboratorio para CI, si su política lo permite. Pide al
administrador el ARN de un rol de ejecución ECS existente y un bucket S3
privado y versionado. Si tienes permiso para crear el bucket, ve a
**S3 → General purpose buckets → Create bucket**, elige la región del
sandbox, conserva **Block all public access** y habilita **Bucket
Versioning**. Usa la misma región y cuenta para los recursos del reto.
Si el administrador suministra
un rol de despliegue para que lo asuman las credenciales del laboratorio,
configura su ARN en `AWS_DEPLOY_ROLE_ARN`. Si las credenciales ya tienen
permisos de despliegue, omite esa variable. Para esta modalidad, añade
`AWS_SESSION_TOKEN` junto a los otros dos secretos y actualiza los tres
cuando expire la sesión. El rol de ejecución debe confiar en
`ecs-tasks.amazonaws.com` y permitir la descarga de imágenes de ECR y
la escritura de logs. La identidad de despliegue necesita `iam:PassRole`
sobre ese rol, acceso al bucket y permisos para ECR, ECS, VPC,
Elastic Load Balancing y CloudWatch Logs. `bootstrap.sh` contiene la
política de ejemplo para el administrador.

Si tu sandbox ya tiene OIDC configurado, el workflow también puede usarlo.
Define `AWS_DEPLOY_ROLE_ARN` y omite los tres secretos de credenciales.
La relación de confianza del rol debe validar `aud` y el `sub` exacto de
este repositorio y su rama `main`. Revisa el formato con los IDs numéricos
del propietario y del repositorio para repositorios nuevos.

[Rol de ejecución ECS](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_execution_IAM_role.html) · [OIDC de GitHub con AWS](https://docs.github.com/es/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws)

## 4. Sube el código y ejecuta el pipeline

1. Descomprime el ZIP en Windows. Copia **el contenido** de la carpeta
   `reto-java-ecs` a la raíz del repositorio clonado, incluida la carpeta
   `.github`. Reemplaza el README inicial.
2. En GitHub Desktop, revisa los archivos, escribe un mensaje de commit y
   pulsa **Commit to main → Push origin**.
3. En GitHub, comprueba que el archivo esté en `.github/workflows/deploy.yml`.
   Abre **Actions → Java en ECS**. Los cambios de código o infraestructura en
   `main` ejecutan el despliegue. Para lanzarlo manualmente o repetirlo después
   de configurar AWS, elige **Run workflow → main → deploy → Run workflow**.

Si usas el navegador, puedes arrastrar los archivos y carpetas descomprimidos
desde **Code → Add file → Upload files**. Verifica las rutas del repositorio
después de guardar. Si falta el workflow, usa **Add file → Create new file**,
escribe `.github/workflows/deploy.yml` como nombre y copia el contenido del
archivo del ZIP. Comprueba también los archivos `.terraform.lock.hcl` dentro
de las dos carpetas de Terraform.

GitHub Actions compila y prueba el contenedor en su runner. Si tienes Docker
en tu equipo y quieres probarlo antes de subirlo, ejecuta estos comandos en
la raíz del proyecto y abre `http://localhost:8080/`.

```bash
docker build -t reto-java-ecs:local .
docker run --rm -p 8080:8080 reto-java-ecs:local
```

[Ejecución manual en GitHub Actions](https://docs.github.com/es/actions/how-tos/manage-workflow-runs/manually-run-a-workflow) · [Docker en varias etapas](https://docs.docker.com/get-started/docker-concepts/building-images/multi-stage-builds/)

## 5. Comprueba y entrega

Abre la ejecución verde en **Actions → Java en ECS → Summary** y pulsa
**Abrir aplicación**. El enlace público usa el DNS de un Application Load
Balancer. Comprueba las tres rutas de la tabla inicial y pega el enlace
de la aplicación en el README después del despliegue. Entrega el enlace
al repositorio y al endpoint. Si el repositorio es privado, comprueba que
el evaluador tenga acceso.

| Dónde comprobar | Qué debe verse |
| --- | --- |
| GitHub Actions | Ejecución verde, URL, SHA del commit e imagen por digest |
| AWS → ECR → Repositories → reto-java-ecs | Imagen etiquetada con el SHA |
| AWS → ECS → Clusters → reto-java-ecs → Services | Servicio activo y 1 tarea en ejecución |
| Navegador | `Hola mundo desde AWS ECS` al abrir la URL pública |

### Si falla un paso

| Mensaje o síntoma | Qué revisar |
| --- | --- |
| `InvalidClientTokenId` o `ExpiredToken` | La pareja de claves corresponde al mismo usuario. Para una sesión temporal, actualiza las dos claves y el token juntos. |
| `AccessDenied` al autenticar o usar S3 | Revisa el ARN del rol de despliegue, los permisos del bucket y que el bucket pertenezca a la misma cuenta de AWS. |
| `AccessDenied` al crear recursos | Identifica la acción denegada en el log. Si el error menciona una SCP, consulta al administrador de la sandbox por esa acción y región. |
| `iam:PassRole` o `ECS was unable to assume the role` | Comprueba el ARN de ejecución, su confianza en ECS y el permiso para pasarle ese rol. |
| `CannotPullContainerError` | Revisa el rol de ejecución, la imagen ECR y que la tarea tenga IP pública y una ruta a Internet para llegar al registro. |
| `503` o tareas que se reinician | Revisa **ECS → servicio → Events**, el target group del balanceador y el grupo `/ecs/reto-java-ecs` de CloudWatch Logs. La comprobación de salud usa `/health` en el puerto 8080. |

## 6. Retira los recursos después de la evaluación

Mantén el endpoint activo durante la revisión. El balanceador, Fargate y
las IPv4 públicas pueden generar consumo en tu cuenta. Después, en
**Actions → Java en ECS → Run workflow**, elige `destroy` en `main`.
Esa operación elimina el servicio, el balanceador y su red, el grupo de
logs y el repositorio ECR con sus imágenes. Una vez que termine, desactiva
o elimina la clave de `reto-java-ecs-ci` y borra sus secretos de GitHub.
Puedes conservar el bucket de estado para reutilizar el proyecto o
eliminarlo cuando hayas terminado, junto con los roles y el usuario del
reto. S3 exige vaciar todas las versiones antes de eliminar un bucket
versionado.

[Precios de AWS Fargate](https://aws.amazon.com/fargate/pricing/) · [Precios de Elastic Load Balancing](https://aws.amazon.com/elasticloadbalancing/pricing/) · [Vaciar un bucket S3](https://docs.aws.amazon.com/AmazonS3/latest/userguide/empty-bucket.html)

## Archivos del proyecto

| Archivo o carpeta | Función |
| --- | --- |
| `src/main/java/demo/App.java`, `pom.xml` | Servicio HTTP y compilación Maven |
| `Dockerfile` | Primera etapa con JDK y Maven, segunda etapa con JRE y JAR |
| `infra/registry/` | Terraform para ECR, con estado independiente |
| `infra/service/` | Terraform para VPC, ECS Fargate, balanceador y logs |
| `.github/workflows/deploy.yml` | Publicación, despliegue y prueba del endpoint |
| `bootstrap.sh` | Preparación inicial de credenciales y estado remoto |
