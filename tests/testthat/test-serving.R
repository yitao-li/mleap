context("save/load/predict")

sc <- testthat_spark_connection()

test_that("We can export and use pipeline model", {
  library(sparklyr)
  mtcars_tbl <- sdf_copy_to(sc, mtcars, overwrite = TRUE)
  pipeline <- ml_pipeline(sc) %>%
    ft_binarizer("hp", "big_hp", threshold = 100) %>%
    ft_vector_assembler(c("big_hp", "wt", "qsec"), "features") %>%
    ml_gbt_regressor(label_col = "mpg")
  pipeline_model <- sparklyr::ml_fit(pipeline, mtcars_tbl)
  
  # export model
  model_path <- file.path(tempdir(), "mtcars_model.zip")
  expect_message(ml_save_bundle(pipeline_model, 
                 sparklyr::ml_transform(pipeline_model, mtcars_tbl),
                 model_path,
                 overwrite = TRUE),
                 "Model successfully exported"
  )
  
  # load model
  model <- mleap_load_bundle(model_path)

  # # check model schema
  expect_known_output(
    mleap_model_schema(model),
    output_file("mtcars_model_schema.txt"),
    print = TRUE
  )
  
  newdata <- tibble::tribble(
    ~qsec, ~hp, ~wt,
    16.2,  101, 2.68,
    18.1,  99,  3.08
  )
  
  transformed_df <- mleap_transform(model, newdata)
  
  expect_identical(dim(transformed_df), c(2L, 6L))
  expect_identical(colnames(transformed_df),
                   c("qsec", "hp", "wt", "big_hp", "features", "prediction")
                   )
})

test_that("We can export a list of transformers", {
  library(sparklyr)
  iris_tbl <- sdf_copy_to(sc, iris, overwrite = TRUE)
  string_indexer <- ft_string_indexer(sc, "Species", "label", dataset = iris_tbl)
  pipeline <- ml_pipeline(string_indexer) %>%
    ft_vector_assembler(c("Petal_Width", "Petal_Length"), "features") %>%
    ml_logistic_regression() %>%
    ft_index_to_string("prediction", "predicted_label",
                       labels = ml_labels(string_indexer))
  pipeline_model <- ml_fit(pipeline, iris_tbl)
  stages <- pipeline_model %>%
    ml_stages(c("vector_assembler", "logistic", "index_to_string"))
  transformed_tbl <- stages %>%
    purrr::reduce(sdf_transform, .init = iris_tbl)
  model_path <- file.path(tempdir(), "mtcars_model.zip")
  
  expect_message(
    ml_save_bundle(stages, transformed_tbl, model_path, overwrite = TRUE),
    "Model successfully exported"
  )
  
  # load model
  model <- mleap_load_bundle(model_path)

  expect_known_output(
    mleap_model_schema(model),
    output_file("iris_model_schema.txt"),
    print = TRUE
  )
  
  newdata <- tibble::tribble(
    ~Petal_Width, ~Petal_Length,
    1.4,          0.2,
    5.2,          1.8
  )

  transformed_df <- mleap_transform(model, newdata)

  expect_identical(dim(transformed_df), c(2L, 7L))
  expect_identical(colnames(transformed_df),
                   c("Petal_Width", "Petal_Length", "features",
                     "rawPrediction", "probability", "prediction",
                     "predicted_label")
  )
  expect_identical(transformed_df$predicted_label,
                   c("setosa", "virginica"))

})