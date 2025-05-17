#!/bin/bash

# --- ビルドパラメータ ---
BOARD="seeeduino_xiao_ble"
ZMK_CONFIG_PATH="/workspaces/zmk-config/config"
ZMK_EXTRA_MODULES_PATH="/workspaces/zmk-config"
FINAL_OUTPUT_BASE_DIR="/workspaces/zmk-config/config/build" # ホストOSの最終的な出力先
TEMP_BUILD_ARTIFACTS_DIR="/tmp/zmk_build_artifacts_$(date +%s)" # 一時的なビルド成果物置き場 (実行毎にユニーク)

# --- ログディレクトリ ---
LOG_DIR="/workspaces/zmk/build_logs" # コンテナ内のログ置き場
mkdir -p "${LOG_DIR}"

# --- バックアップ関数 (最終成果物配置時に使用) ---
# $1: source_file (一時作業ディレクトリ内のファイル)
# $2: dest_file_name (最終的なファイル名)
# $3: shield_name_for_log (ログ表示用のシールド名)
# $4: master_backup_dir_path (共通バックアップディレクトリのパス。空文字の場合はバックアップ処理をスキップ)
backup_final_artifact() {
    local source_file=$1
    local dest_file_name=$2
    local shield_name_for_log=$3
    local master_backup_dir_path=$4
    local dest_full_path="${FINAL_OUTPUT_BASE_DIR}/${dest_file_name}"

    if [ -f "${dest_full_path}" ]; then
        if [ -n "${master_backup_dir_path}" ]; then # 共通バックアップディレクトリパスが指定されているか
            echo "Backup (${shield_name_for_log}): Found existing final artifact at ${dest_full_path}"
            # 共通バックアップディレクトリは呼び出し元で作成されている想定
            echo "Backup (${shield_name_for_log}): Moving existing final artifact to ${master_backup_dir_path}/${dest_file_name}"
            mv "${dest_full_path}" "${master_backup_dir_path}/${dest_file_name}"
        else
            # 既存ファイルはあるが、共通バックアップディレクトリが指定されていない場合 (通常は発生しないはず)
            echo "Warning (${shield_name_for_log}): Existing file found at ${dest_full_path}, but no master backup directory specified. Overwriting."
        fi
    fi

    echo "Copying final artifact ${source_file} to ${dest_full_path} (${shield_name_for_log})"
    cp "${source_file}" "${dest_full_path}"
}

# --- 個別ビルド関数 ---
# $1: シールド名
# $2: ビルドディレクトリ名 (例: build/roba_r)
# $3: 出力UF2ファイル名 (例: roBa_R-seeeduino_xiao_ble-zmk.uf2)
# $4: スニペット名 (オプション)
run_build() {
    local shield_name=$1
    local build_dir=$2
    local output_uf2_name=$3
    local snippet_arg=$4
    local log_file="${LOG_DIR}/${shield_name}_build.log"

    echo "Starting ${shield_name} build... Log: ${log_file}"
    rm -rf "${build_dir}" # クリーンビルド

    local west_build_cmd="west build -s app -b ${BOARD} -d ${build_dir} -- -DSHIELD=${shield_name} -DZMK_CONFIG=${ZMK_CONFIG_PATH} -DZMK_EXTRA_MODULES=${ZMK_EXTRA_MODULES_PATH}"
    if [ -n "${snippet_arg}" ]; then
        west_build_cmd+=" -DSNIPPET=${snippet_arg}"
    fi

    # ビルドコマンドの実行とログ記録
    if ${west_build_cmd} > "${log_file}" 2>&1; then
        # ビルド成功時、一時ディレクトリに成果物をコピー
        mkdir -p "${TEMP_BUILD_ARTIFACTS_DIR}"
        cp "${build_dir}/zephyr/zmk.uf2" "${TEMP_BUILD_ARTIFACTS_DIR}/${output_uf2_name}"
        echo "${shield_name} build successful. Artifact: ${TEMP_BUILD_ARTIFACTS_DIR}/${output_uf2_name}"
        return 0 # 成功
    else
        echo "${shield_name} build FAILED. Check log: ${log_file}"
        return 1 # 失敗
    fi
}

# --- 事前に一時作業ディレクトリと最終出力ディレクトリを作成 ---
mkdir -p "${TEMP_BUILD_ARTIFACTS_DIR}"
mkdir -p "${FINAL_OUTPUT_BASE_DIR}" # ユーザーが事前に作成していなくてもエラーにならないように

# --- 各ビルドをバックグラウンドで実行 ---
run_build "roBa_R" "build/roba_r" "roBa_R-${BOARD}-zmk.uf2" "studio-rpc-usb-uart" &
PID_R=$!

run_build "roBa_L" "build/roba_l" "roBa_L-${BOARD}-zmk.uf2" &
PID_L=$!

run_build "settings_reset" "build/settings_reset" "settings_reset-${BOARD}-zmk.uf2" &
PID_RESET=$!

# --- 全てのバックグラウンドジョブの終了を待つ ---
echo "Waiting for all builds to complete..."
FAIL_COUNT=0
FAILED_BUILDS=()

wait $PID_R || { FAILED_BUILDS+=("roBa_R"); FAIL_COUNT=$((FAIL_COUNT+1)); }
wait $PID_L || { FAILED_BUILDS+=("roBa_L"); FAIL_COUNT=$((FAIL_COUNT+1)); }
wait $PID_RESET || { FAILED_BUILDS+=("settings_reset"); FAIL_COUNT=$((FAIL_COUNT+1)); }

# --- 結果処理 ---
if [ $FAIL_COUNT -eq 0 ]; then
    echo "All builds completed successfully!"
    echo "Moving artifacts to final destination: ${FINAL_OUTPUT_BASE_DIR}"

    master_backup_dir_for_this_run="" # この実行での共通バックアップディレクトリパスを初期化

    # バックアップ対象となる既存ファイルが FINAL_OUTPUT_BASE_DIR にあるか事前に確認
    existing_files_found=false
    if [ -d "${TEMP_BUILD_ARTIFACTS_DIR}" ] && [ "$(ls -A "${TEMP_BUILD_ARTIFACTS_DIR}")" ]; then # 一時ディレクトリが存在し、空でない場合
        for artifact_to_check in $(ls "${TEMP_BUILD_ARTIFACTS_DIR}"); do
            if [ -f "${FINAL_OUTPUT_BASE_DIR}/${artifact_to_check}" ]; then
                existing_files_found=true
                break
            fi
        done
    fi

    if [ "$existing_files_found" = true ]; then
        # ユーザー指定フォーマット YYYYMMDD_HH-MM_backup
        master_backup_dir_for_this_run="${FINAL_OUTPUT_BASE_DIR}/$(TZ=Asia/Tokyo date +"%Y%m%d_%H-%M")_backup"
        echo "Existing artifacts found. Creating master backup directory: ${master_backup_dir_for_this_run}"
        mkdir -p "${master_backup_dir_for_this_run}"
    fi

    if [ -d "${TEMP_BUILD_ARTIFACTS_DIR}" ] && [ "$(ls -A "${TEMP_BUILD_ARTIFACTS_DIR}")" ]; then
        for artifact_file in $(ls "${TEMP_BUILD_ARTIFACTS_DIR}"); do
            shield_name_from_artifact=$(echo "${artifact_file}" | cut -d'-' -f1)
            backup_final_artifact "${TEMP_BUILD_ARTIFACTS_DIR}/${artifact_file}" "${artifact_file}" "${shield_name_from_artifact}" "${master_backup_dir_for_this_run}"
        done
        echo "All artifacts moved."
    else
        echo "No build artifacts found in temporary directory. Skipping move."
    fi
else
    echo "${FAIL_COUNT} build(s) failed: ${FAILED_BUILDS[*]}"
    echo "Build artifacts were NOT moved to the final destination due to errors."
    echo "Intermediate build artifacts (if any) are in: ${TEMP_BUILD_ARTIFACTS_DIR}"
    echo "Check individual log files in ${LOG_DIR} for details."
    # exit 1 # エラーがあった場合は終了コード1で抜ける (CI等で利用する場合)
fi

# スクリプト終了時に一時ディレクトリを削除するかどうかは運用次第
# echo "Cleaning up temporary build artifacts directory: ${TEMP_BUILD_ARTIFACTS_DIR}"
# rm -rf "${TEMP_BUILD_ARTIFACTS_DIR}"

echo "Script finished."
