class DataController < ApplicationController
  def upload
    if request.post?
      data_file = DataFile.new(params[:upload])
      render :text => "#{data_file.dates}, #{data_file.prices}, #{data_file.volume}"
    end
  end

end
