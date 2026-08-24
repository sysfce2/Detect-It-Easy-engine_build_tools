message("Init translation")

# Ensure translation directory exists
file(MAKE_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/translation)

# Use absolute paths for translation files
set(TS_FILES
    ${CMAKE_CURRENT_SOURCE_DIR}/translation/${X_ORIGINAL_FILENAME}_ar.ts
    ${CMAKE_CURRENT_SOURCE_DIR}/translation/${X_ORIGINAL_FILENAME}_bn.ts
    ${CMAKE_CURRENT_SOURCE_DIR}/translation/${X_ORIGINAL_FILENAME}_de.ts
    ${CMAKE_CURRENT_SOURCE_DIR}/translation/${X_ORIGINAL_FILENAME}_es.ts
    ${CMAKE_CURRENT_SOURCE_DIR}/translation/${X_ORIGINAL_FILENAME}_fa.ts
    ${CMAKE_CURRENT_SOURCE_DIR}/translation/${X_ORIGINAL_FILENAME}_fr.ts
    ${CMAKE_CURRENT_SOURCE_DIR}/translation/${X_ORIGINAL_FILENAME}_he.ts
    ${CMAKE_CURRENT_SOURCE_DIR}/translation/${X_ORIGINAL_FILENAME}_id.ts
    ${CMAKE_CURRENT_SOURCE_DIR}/translation/${X_ORIGINAL_FILENAME}_it.ts
    ${CMAKE_CURRENT_SOURCE_DIR}/translation/${X_ORIGINAL_FILENAME}_ja.ts
    ${CMAKE_CURRENT_SOURCE_DIR}/translation/${X_ORIGINAL_FILENAME}_ko.ts
    ${CMAKE_CURRENT_SOURCE_DIR}/translation/${X_ORIGINAL_FILENAME}_pl.ts
    ${CMAKE_CURRENT_SOURCE_DIR}/translation/${X_ORIGINAL_FILENAME}_pt_BR.ts
    ${CMAKE_CURRENT_SOURCE_DIR}/translation/${X_ORIGINAL_FILENAME}_pt_PT.ts
    ${CMAKE_CURRENT_SOURCE_DIR}/translation/${X_ORIGINAL_FILENAME}_ru.ts
    ${CMAKE_CURRENT_SOURCE_DIR}/translation/${X_ORIGINAL_FILENAME}_sv.ts
    ${CMAKE_CURRENT_SOURCE_DIR}/translation/${X_ORIGINAL_FILENAME}_tr.ts
    ${CMAKE_CURRENT_SOURCE_DIR}/translation/${X_ORIGINAL_FILENAME}_uk.ts
    ${CMAKE_CURRENT_SOURCE_DIR}/translation/${X_ORIGINAL_FILENAME}_vi.ts
    ${CMAKE_CURRENT_SOURCE_DIR}/translation/${X_ORIGINAL_FILENAME}_zh.ts
    ${CMAKE_CURRENT_SOURCE_DIR}/translation/${X_ORIGINAL_FILENAME}_zh_TW.ts
)
